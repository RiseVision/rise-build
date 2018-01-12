#!/usr/bin/env bash

. ./docker/build-assets/scripts/utils.sh

if [ ! -d "core" ]; then
    echo "X please clone core in core/folder"
    exit 1
fi

if ! [ -x "$(command -v docker)" ]; then
    echo "X Please install docker"
    exit 1
fi


VERSION=$(cat core/package.json | jq -r ".version")

read -r -p "Do you want to build version $VERSION? (y/n): " YN

if [ "$YN" != "y" ]; then
    exit 0;
fi

read -r -p "Is this a mainnet build? (y/n): " YN

if [ "$YN" == "y" ]; then
    NETWORK="mainnet"
else
    NETWORK="testnet"
fi


cd docker

echo "Creating build environment…"
sleep 2
exec_cmd "docker build . -t rise_build_env"
exit_if_prevfail
echo "√ Environment built"
sleep 2

cd ..
echo "Creating package…"
sleep 2
exec_cmd "docker run --rm -v $(pwd):/home/rise/tar -v $(pwd)/core:/home/rise/core rise_build_env"
exit_if_prevfail

FINAL_NAME="rise_${VERSION}_${NETWORK}.tar.gz"
mv out.tar.gz rise_${VERSION}_${NETWORK}.tar.gz

echo "√ Image created. ${FINAL_NAME}"
