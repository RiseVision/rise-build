#!/usr/bin/env bash
#
# Copyright (C) 2019 Rise Vision PLC
# Copyright (C) 2017 Lisk Foundation
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
######################################################################

# Make sure that if anything fails the command script stops executing
set -e

DOWNLOAD_BASEURL=${DOWNLOAD_BASEURL:-"https://downloads.rise.vision/core/"}
INSTALL_DIR="./rise"
LOG_FILE=install.out
MINSPACE=`df -k --output=avail "$PWD" | tail -n1`  

GC="$(tput setaf 2)√$(tput sgr0)"
RX="$(tput setaf 1)X$(tput sgr0)"
YE="$(tput setaf 3)‼$(tput sgr0)"

if [[ $EUID -eq 0 ]]; then
    echo "$RX This script should not be run using sudo or as root. Please run it as a regular user."
    exit 1
fi

if [ "$(uname)" != "Linux" ]; then
    echo "$RX $(uname) is not an allowed operating system"
    exit 1
fi

if [[ $MINSPACE -lt 2621440 ]]; then
    echo -e "$RX Not enough free space in $PWD to install the node."
    exit 1
fi;

case "$(uname -m)" in
    "x86_64") ARCH="x86" ;;
    "armv7l") ARCH="arm" ;;
    *)
        echo "$RX $(uname -m) is an invalid architecture."
        exit 1
        ;;
esac

# Setup logging
exec > >(tee -ia $LOG_FILE)
exec 2>&1

# export LC_ALL=en_US.UTF-8
# export LANG=en_US.UTF-8
# export LANGUAGE=en_US.UTF-8

check_prerequisites() {

    if [[ ! -f /usr/bin/sudo ]]; then
        echo "$RX Install sudo as root user before continuing."
        echo "Ubuntu Issue: apt-get install sudo"
        echo "Redhat/Centos Issue: yum install sudo"
        echo "Also make sure that your user has sudo access."
        exit 2
    fi

    if ! sudo -n true 2>/dev/null; then
        echo "Please provide sudo password for validation"
        if sudo -Sv -p ''; then
            echo -e "Sudo authenticated.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
            else
            echo -e "Unable to authenticate Sudo.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
            exit 2
        fi
    fi

    if [ -f /etc/redhat-release ]; then
        packageList="epel-release jq wget curl tar"

        for packageName in $packageList; do
            rpm --quiet --query $packageName || sudo yum install -q -y $packageName > /dev/null 2>&1
        done
    fi

    if [ -f /etc/lsb-release ]; then
        packageList="wget curl tar coreutils"

        for packageName in $packageList; do
            apt -qq list $packageName 2>&1 >/dev/null| grep install || sudo apt-get --yes install $packageName
        done   
    fi
}

command_check() {
    if [ ! -x "$(command -v "$1")" ]; then
        echo "$RX $1 executable cannot be found. Please install"
        exit 1
    fi
}

usage() {
    echo "Usage: $0 <install|upgrade> [-r <mainnet|testnet>] [-n] [-t] [-u <URL>]"
    echo "install         -- install"
    echo "upgrade         -- upgrade"
    echo " -r <RELEASE>   -- choose mainnet or testnet"
    echo " -u             -- release url"
    echo " -n             -- install ntp"
    echo " -t             -- set timezone to UTC"
}

parse_option() {
    OPTIND=2
    while getopts :d:r:u:hn0: OPT; do
        case "$OPT" in
             r) NETWORK="$OPTARG" ;;
             n) INSTALL_NTP=1 ;;
             t) SET_TIMEZONE=1 ;;
             u) URL="$OPTARG" ;;
        esac
     done

    if [ "$NETWORK" ]; then
        if [[ "$NETWORK" != "testnet" && "$NETWORK" != "mainnet" ]]; then
            echo "-r <testnet|mainnet>"
            usage
            exit 1
        fi
    else
        if [ -f "${INSTALL_DIR}/etc/.network" ]; then
            NETWORK=$(head -1 "${INSTALL_DIR}/etc/.network");
        else
            NETWORK="mainnet"
        fi
    fi

    if [ "$URL" == "" ]; then
        FILE_BASE=$([ "$ARCH" == "arm" ] && echo "latest.arm" || echo "latest")
        URL="${DOWNLOAD_BASEURL}${NETWORK}/${FILE_BASE}.tar.gz"
    fi

    FILE=$(basename "$URL")

}

set_timezone() {
    if [ "$(date +%Z)" == "UTC" ]; then
        echo "$GC Timezone is UTC"
    elif [ $(systemd-detect-virt -c) != "none" ]; then
        echo "$YE Your host is running in a Docker, LXC or OpenVZ container. Timezones must be set on host"
    elif [ -x "$(command -v timedatectl)" ]; then
        [ "$SET_TIMEZONE" ] || read -r -n 1 -p "Would like to set the system timezone to UTC? (y/n): " REPLY
        echo ""
        if [[ "$SET_TIMEZONE" || "$REPLY" =~ ^[Yy]$ ]]; then
            timedatectl set-timezone UTC
            if sudo pgrep -x "ntpd" > /dev/null; then
                timedatectl set-ntp 1
            fi
            echo "$GC Timezone set to UTC"
        else
            echo "$YE Timezone not set"
        fi
    else
        echo "$YE Timezone could not be set"
    fi
}

ntp() {
    if [ $(systemd-detect-virt -c) != "none" ]; then
        echo "$YE Your host is running in a Docker, LXC or OpenVZ container, and NTP is not compatible."
        echo "   Your node may lose blocks or stay behind due to wrong clock sync."
    elif [[ -f "/etc/debian_version" &&  ! -f "/proc/user_beancounters" ]]; then
        if sudo pgrep -x "ntpd" > /dev/null; then
            echo "$GC NTP is running"
        else
            echo "$RX NTP is not running"
            [ "$INSTALL_NTP" ] || read -r -n 1 -p "Would like to install NTP? (y/n): " REPLY
            if [[ "$INSTALL_NTP" || "$REPLY" =~ ^[Yy]$ ]]; then
                echo -e "\nInstalling NTP.\n"
                sudo apt-get install ntp ntpdate -yyq
                sudo service ntp stop
                sudo ntpdate pool.ntp.org
                sudo service ntp start
                if sudo pgrep -x "ntpd" > /dev/null; then
                    echo "$GC NTP is running"
                else
                    echo -e "\nCore requires NTP running on Debian based systems. Please check /etc/ntp.conf and correct any issues."
                    exit 0
                fi
            else
                echo -e "\nCore requires NTP on Debian based systems, exiting."
                exit 0
            fi
        fi # End Debian Checks
    elif [[ -f "/etc/redhat-RELEASE" &&  ! -f "/proc/user_beancounters" ]]; then
        if sudo pgrep -x "ntpd" > /dev/null; then
            echo "$GC NTP is running"
        else
            if sudo pgrep -x "chronyd" > /dev/null; then
                echo "$GC Chrony is running"
            else
                echo "$RX NTP and Chrony are not running"
                [ "$INSTALL_NTP" ] || read -r -n 1 -p "Would like to install NTP? (y/n): " REPLY
                if [[ "$INSTALL_NTP" || "$REPLY" =~ ^[Yy]$ ]]; then
                    echo -e "\nInstalling NTP, please provide sudo password.\n"
                    sudo yum -yq install ntp ntpdate ntp-doc
                    sudo chkconfig ntpd on
                    sudo service ntpd stop
                    sudo ntpdate pool.ntp.org
                    sudo service ntpd start
                    if pgrep -x "ntpd" > /dev/null; then
                        echo "$GC NTP is running"
                    else
                        echo -e "\nCore requires NTP running on Debian based systems. Please check /etc/ntp.conf and correct any issues."
                        exit 0
                    fi
                else
                    echo -e "\nCore requires NTP or Chrony on RHEL based systems, exiting."
                    exit 0
                fi
            fi
        fi # End Redhat Checks
    elif [[ -f "/proc/user_beancounters" ]]; then
        echo "$YE Running OpenVZ VM, NTP and Chrony are not compatible"
    fi
}

download() {
    if [ -f "$FILE" ]; then
        echo "Removing old download file: $FILE"
        rm $FILE;
    fi
    if [ -f "$FILE.sha1" ]; then
        echo "Removing old download file: $FILE.sha1"
        rm $FILE.sha1;
    fi

    echo "Downloading core from ${URL}"
    wget -q $URL >> /dev/null
    wget -q "${URL}.sha1" >> /dev/null

    if [ -f "$FILE" ]; then
        echo "$GC Core downloaded!"
    fi
    sha1sum -c ${FILE}.sha1 > /dev/null
    if [ ! "$?" -eq 0 ]; then
        echo "$RX sha1sum does not match";
        exit 1
    else
        echo "$GC Checksum matches. Proceeding...";
    fi

}

install() {
    if [ ! -f "$FILE" ]; then
        echo "$RX tar.gz does not exist!"
        exit 1
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir "$INSTALL_DIR"
    fi
    echo "Extracting core code"
    tar -zxf "$FILE" -C "$INSTALL_DIR"
    if [ "$?" -eq 0 ]; then
        echo "$GC Core code files extracted"
    else
        echo "$RX Failure when extracting files"
        exit 1
    fi
}

start_node() {
    echo "Starting node."
    pushd . > /dev/null
    cd ${INSTALL_DIR}
    ./manager.sh start all > /dev/null
    sleep 8
    if ! (./manager.sh status | grep -q "NODE is running") ; then
        echo "$RX Node is not running :("
        exit 1
    fi
    if ! (./manager.sh status | grep -q "DB is running") ; then
        echo "$RX DB is not running :("
        exit 1
    fi
    if ! (./manager.sh status | grep -q "Redis is running") ; then
        echo "$RX Redis is not running :("
        exit 1
    fi

    echo "$GC Core and dependencies running"

    popd > /dev/null

}

cleanup() {
    rm -f ${FILE} ${FILE}.sha1
    rm -f $LOG_FILE
    rm -f $0
}

case $1 in
    "install")
        parse_option "$@"
        check_prerequisites
        ntp
        set_timezone
        download
        install
        # set the network file.
        if [ ! -f "${INSTALL_DIR}/etc/.network" ]; then
	        echo $NETWORK > "${INSTALL_DIR}/etc/.network"
	    fi
        start_node
        cleanup
        echo "Installation completed"
        ;;
    "upgrade")
        pushd . > /dev/null
        parse_option "$@"
        download
        cd ${INSTALL_DIR}
        ./manager.sh stop all
        popd > /dev/null
        echo "Creating backup"
        tar -czf backup.tgz ${INSTALL_DIR} --exclude "${INSTALL_DIR}/data/backups" >> /dev/null 2>&1
        echo "$GC Backup created"
        if [ -d "${INSTALL_DIR}-old" ]; then
            echo "Removing old backup..."
            rm -rf ${INSTALL_DIR}-old
        fi
        mv ${INSTALL_DIR} ${INSTALL_DIR}-old
        install
        # copy all data
        cp -a ${INSTALL_DIR}-old/data/. ${INSTALL_DIR}/data
        cp -a ${INSTALL_DIR}-old/etc/. ${INSTALL_DIR}/etc
        cp -a ${INSTALL_DIR}-old/.pm2 ${INSTALL_DIR}/
        start_node
        cleanup
        ;;
    *)
        usage
        ;;

esac
