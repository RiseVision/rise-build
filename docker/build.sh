#!/bin/bash

if [ ! -d ./core ]; then
    echo "Please mount volume with core please."
fi

VERSION=$(cat core/package.json | ./jq/jq -r '.version')
BRANCH=$(cd core/; git symbolic-ref --short HEAD)

echo "Building $VERSION from branch ${BRANCH}..."


# copy core data to out/src
cp -a ./core/ out/
mv out/core out/src
rm -rf out/src/.git
sudo chown $(whoami):$(whoami) -R ./out/src


# copy redis commands to bin folder.
mv redis/src/{redis-cli,redis-server} out/bin

# copy logrotate command to bin folder
mv logrotate/logrotate out/bin

# copy postgres stuff
cp -a postgres/{lib,bin,share} out/

cp jq/jq out/bin

# copy libreadline and libhistory
READLINE_VERSION=$(ls readline/shlib | grep libreadline | awk -F'[^0-9]*' '{print $2}')
cp -vf readline/shlib/{libhistory.so.$READLINE_VERSION.0,libreadline.so.$READLINE_VERSION.0}  out/lib
cp -vf readline/{libhistory.a,libreadline.a}  out/lib
cd out/lib
ln -s libreadline.so.$READLINE_VERSION.0 libreadline.so.$READLINE_VERSION
ln -s libreadline.so.$READLINE_VERSION.0 libreadline.so
ln -s libhistory.so.$READLINE_VERSION.0 libhistory.so.$READLINE_VERSION
ln -s libhistory.so.$READLINE_VERSION.0 libhistory.so

# COPY over node
cd ~
cp -a ./node/lib/node_modules ./out/lib
cp -a ./node/bin/* ./out/bin

cd
export PATH="$(pwd)/postgres/bin:$(pwd)/yarn/bin:$(pwd)/out/bin:$PATH"
export LD_LIBRARY_PATH="$(pwd)/postgres/lib:$(pwd)/out/lib:$LD_LIBRARY_PATH"

cd out/src
rm -rf node_modules
yarn install
./node_modules/.bin/lerna bootstrap
chrpath -d "$(pwd)/node_modules/sodium/deps/libsodium/test/default/.libs/"*
chrpath -d "$(pwd)/../lib/libreadline.so.$READLINE_VERSION.0"
chrpath -d "$(pwd)/../lib/libhistory.so.$READLINE_VERSION.0"

yarn transpile
./node_modules/.bin/lerna link

# Copy Build file
echo -n $COMMITSHA > build
# Create script symlinks
cd ..
ln -s ./scripts/manager.sh manager.sh
ln -s ../data/pg/postmaster.pid ./pids/pg.pid


# install pm2

npm i pm2 -g >> /dev/null

cd ..
echo "Creating Tar.gz FILE"
sudo tar -czf tar/out.tar.gz -C ./out .
sudo chown $(stat -c '%u' ./tar):$(stat -c '%g' ./tar) tar/out.tar.gz
