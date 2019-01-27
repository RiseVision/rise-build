#!/usr/bin/env bash

. ./docker/build-assets/scripts/utils.sh
. ./docker/build-assets/scripts/env_vars.sh

if [ ! -d "core" ]; then
    echo "X please clone core in core/folder"
    exit 1
fi

if ! [ -x "$(command -v docker)" ]; then
    echo "X Please install docker"
    exit 1
fi

COMMITSHA=$(cd core; git show -s --format=%h)

if [ "$VERSION" == "" ]; then
    VERSION=$(cat core/package.json | jq -r ".version")
    read -r -p "Do you want to build version $VERSION? (y/n): " YN

    if [ "$YN" != "y" ]; then
        exit 0;
    fi
fi

if [ "$NETWORK" == "" ]; then
    read -r -p "Is this a mainnet build? (y/n): " YN

    if [ "$YN" == "y" ]; then
        NETWORK="mainnet"
    else
        NETWORK="testnet"
    fi
fi

if [ "$ARM" == "" ]; then
    read -r -p "Is this an ARM build? (y/n): " YN

    if [ "$YN" == "y" ]; then
        read -r -p "Is this an 64 build? (y/n): " YN
        if [ "$YN" == "y" ]; then
            ARM="ARM64"
        else
            ARM="ARM"
        fi
    fi
fi

if [ "$ARM" == "ARM" ] || [ "$ARM" == "ARM64" ]; then
    LOCAL_QEMU_DEP_LOC="./docker/build-assets/qemu-arm-static"
    if [ "$ARM" == "ARM64" ]; then
        LOCAL_QEMU_DEP_LOC="./docker/build-assets/qemu-aarch64-static"
    fi

    if [ ! -f "$LOCAL_QEMU_DEP_LOC" ]; then
        echo "Copy over your $(basename $LOCAL_QEMU_DEP_LOC) file in $LOCAL_QEMU_DEP_LOC";

    fi

    if [[ ! -x "$LOCAL_QEMU_DEP_LOC" ]]; then
        echo "$(basename $LOCAL_QEMU_DEP_LOC) not executable! Please grant permissions:"
        (set -x; sudo chmod +x "$LOCAL_QEMU_DEP_LOC")
    fi
fi

NAME="rise_${VERSION}_${NETWORK}_${COMMITSHA}"
IMAGE_NAME="rise_build_env"
DOCKERFILE="Dockerfile"

if [ "$ARM" == "ARM" ]; then
    NAME="${NAME}.arm"
    IMAGE_NAME="${IMAGE_NAME}_arm"
    DOCKERFILE="${DOCKERFILE}.arm"
elif [ "$ARM" == "ARM64" ]; then
    NAME="${NAME}.arm64"
    IMAGE_NAME="${IMAGE_NAME}_arm64"
    DOCKERFILE="${DOCKERFILE}.arm64"
else
    NAME="${NAME}.x86_x64"
fi

FINAL_NAME="${NAME}.tar.gz"

cd docker

echo "Creating build environment…"
sleep 2
exec_cmd "docker build -t ${IMAGE_NAME} -f ${DOCKERFILE} ."
exit_if_prevfail
echo "$GC Environment built"
sleep 2

cd ..
echo "Creating package…"
sleep 2
exec_cmd "docker run -it --rm -e \"COMMITSHA=${COMMITSHA}\" -v $(pwd):/home/rise/tar -v $(pwd)/core:/home/rise/core ${IMAGE_NAME}"
exit_if_prevfail

mv out.tar.gz $FINAL_NAME
sha1sum "$FINAL_NAME" > "${FINAL_NAME}.sha1"

echo "$GC Image created. ${FINAL_NAME}"