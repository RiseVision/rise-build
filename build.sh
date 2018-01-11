#!/bin/bash

if [ ! -d ./core ]; then
    echo "Please checkout core please."
fi

VERSION=$(cat core/package.json | ./jq/jq -r '.version')
BRANCH=$(cd core/; git symbolic-ref --short HEAD)

echo "Building $VERSION from branch ${BRANCH}..."


# copy core data to out/src
cp -a ./core/ out/
mv out/core out/src
rm -rf out/src/.git

# copy redis commands to bin folder.
mv redis/src/{redis-cli,redis-server} out/bin

# copy postgres stuff
cp -a postgres/{lib,bin,share} out/

cp jq/jq out/bin

# copy libreadline and libhistory
cp -vf readline/shlib/{libhistory.so.7.0,libreadline.so.7.0}  out/lib
cp -vf readline/{libhistory.a,libreadline.a}  out/lib
cd out/lib
ln -s libreadline.so.7.0 libreadline.so.7
ln -s libreadline.so.7.0 libreadline.so
ln -s libhistory.so.7.0 libhistory.so.7
ln -s libhistory.so.7.0 libhistory.so

# COPY over node and npm
cd ~
cp -a ./node/lib/node_modules ./out/lib
cp -a ./node/bin/* ./out/bin

cd
export PATH="$(pwd)/postgres/bin:$(pwd)/out/bin:$PATH"
export LD_LIBRARY_PATH="$(pwd)/postgres/lib:$(pwd)/out/lib:$LD_LIBRARY_PATH"
echo $PATH;
echo $LD_LIBRARY_PATH;
echo $(pwd);

cd out/src
npm i >> /dev/null
chrpath -d "$(pwd)/node_modules/sodium/deps/libsodium/test/default/.libs/"*
chrpath -d "$(pwd)/../lib/libreadline.so.7.0"
chrpath -d "$(pwd)/../lib/libhistory.so.7.0"

npm run transpile
npm prune  --production >> /dev/null


# Create script symlinks
cd ..
ln -s ./scripts/manager.sh manager.sh
ln -s ../data/pg/postmaster.pid ./pids/pg.pid


# install pm2

npm i pm2 -g