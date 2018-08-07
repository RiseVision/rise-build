#!/bin/bash
# Make sure that if anything fails the command script stops executing
set -e
echo ""

if ! sudo -n true 2>/dev/null; then
    echo "Please provide sudo password for validation"
    if sudo -Sv -p ''; then
        echo -e "Sudo authenticated.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
    else
        echo -e "Unable to authenticate Sudo.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
        exit 2
    fi
fi

echo ""
echo "Please be patient. Installation may take a few minutes depending on your VPS"
echo ""

if [ ! -d ./rise ]; then
	echo "You're not in the right folder"
	exit 1
fi

echo "Performing database backup"
cd rise
./manager.sh backup

if [ ! -f ./data/backups/latest ]; then
	echo "Backup failed"
	exit 1;
fi

BACKUP_NAME=$(readlink data/backups/latest)
BACKUP_FILE="./data/backups/$BACKUP_NAME"

./manager.sh stop all
source scripts/env_vars.sh
# Prevent
pm2 kill

# Move backup file for later restore
mv $BACKUP_FILE ../$BACKUP_NAME
cd ..
[ -f ./install.sh ] && rm install.sh

mv rise rise_1.0.x



wget https://raw.githubusercontent.com/RiseVision/rise-build/master/scripts/install.sh
bash install.sh install -r mainnet -u https://downloads.rise.vision/core/mainnet/rise_1.1.1_mainnet_92f90ea0.tar.gz


echo "Restoring data & backup"
cp -a ./rise_1.0.x/etc/.  ./rise/etc
cp -a ./rise_1.0.x/.pm2   ./rise/
cd rise
./manager.sh restoreBackup ../$BACKUP_NAME
cd ..
echo "Wait for node to apply database upgrades"
sleep 60
echo "All done :)"