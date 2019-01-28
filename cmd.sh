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
        ARM="ARM"
    fi
fi

if [ "$ARM" == "ARM" ]; then
    QEMU_DEP_LOC=/usr/bin/qemu-arm-static
    LOCAL_QEMU_DEP_LOC=./docker/build-assets/qemu-arm-static

    if [ ! -f "$LOCAL_QEMU_DEP_LOC" ]; then
        if [ ! -f "$QEMU_DEP_LOC" ]; then
            echo "Installing $(basename "$QEMU_DEP_LOC")..."
            QEMU_BINS_CONTAINER=$(docker create -it jpopesculian/qemu-user-static-bins:latest)
            sudo docker cp $QEMU_BINS_CONTAINER:/usr/bin/qemu-arm-static /usr/bin/qemu-arm-static
            docker rm $QEMU_BINS_CONTAINER 2&> /dev/null
            sudo docker run --rm --privileged multiarch/qemu-user-static:register --reset
            echo "Done!"
        fi
        if [ ! -f "$QEMU_DEP_LOC" ]; then
            echo "Failed to install 'qemu-user-static' bins! Necessary for ARM builds."
            exit 1
        fi
        echo "Copying $QEMU_DEP_LOC -> $LOCAL_QEMU_DEP_LOC"
        cp "$QEMU_DEP_LOC" "$LOCAL_QEMU_DEP_LOC"
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
exec_cmd "docker run --rm -e \"COMMITSHA=${COMMITSHA}\" -v $(pwd):/home/rise/tar -v $(pwd)/core:/home/rise/core ${IMAGE_NAME}"
exit_if_prevfail

mv out.tar.gz $FINAL_NAME
sha1sum "$FINAL_NAME" > "${FINAL_NAME}.sha1"

echo "$GC Image created. ${FINAL_NAME}"
