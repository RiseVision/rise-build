#!/bin/bash
#
# Copyright (C) 2018 Rise Vision PLC
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

GC="$(tput setaf 2)√$(tput sgr0)"
RX="$(tput setaf 1)X$(tput sgr0)"

if [[ $EUID -eq 0 ]]; then
    echo "$RX This script should not be run using sudo or as root. Please run it as a regular user."

    exit 1
fi

if [ "$(uname)" != "Linux" ]; then
    echo "$RX $(uname) is not an allowed operating system"
	exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "$RX $(uname -m) is an invalid architecture."
	exit 1
fi

MINSPACE=`df -k --output=avail "$PWD" | tail -n1`   
if [[ $MINSPACE -lt 2621440 ]]; then      
    echo -e "There is probably not enough free space in $PWD to run the node.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
	exit 1
fi;

# Setup logging
exec > >(tee -ia $LOG_FILE)
exec 2>&1

# export LC_ALL=en_US.UTF-8
# export LANG=en_US.UTF-8
# export LANGUAGE=en_US.UTF-8

command_check() {
    if [ ! -x "$(command -v "$1")" ]; then
        echo "$RX $1 executable cannot be found. Please install"
        exit 1
    fi
}

check_prerequisites() {
    command_check "wget"
    command_check "curl"
    command_check "tar"
    command_check "sudo"
    command_check "sha1sum"

    if ! sudo -n true 2>/dev/null; then
		echo "Please provide sudo password for validation"
		if sudo -Sv -p ''; then
			echo -e "Sudo authenticated.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
		else
			echo -e "Unable to authenticate Sudo.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
			exit 2
		fi
	fi
}

usage() {
	echo "Usage: $0 <install|upgrade> [-r <mainnet|testnet>] [-n] [-u <URL>]"
	echo "install         -- install"
	echo "upgrade         -- upgrade"
	echo " -r <RELEASE>   -- choose mainnet or testnet"
	echo " -u             -- release url"
}

parse_option() {
	OPTIND=2
	while getopts :d:r:u:hn0: OPT; do
		 case "$OPT" in
			 r) NETWORK="$OPTARG" ;;
			 n) INSTALL_NTP=1 ;;
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
	    URL="${DOWNLOAD_BASEURL}${NETWORK}/latest.tar.gz"
	fi

    FILE=$(basename "$URL")

}

ntp() {
    if [ $(systemd-detect-virt) == "lxc" ] || [ $(systemd-detect-virt) == "openvz" ]; then
        echo "$GC Your host is running in LXC or OpenVZ container. NTP is not required."
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
        echo "_ Running OpenVZ VM, NTP and Chrony are not required"
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
    rm ${FILE} ${FILE}.sha1
    rm $0
}

case $1 in
    "install")
        parse_option "$@"
        check_prerequisites
        ntp
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
