#!/usr/bin/env bash
OLDPATH=$(pwd)
cd "$(cd -P -- "$(dirname -- "$(readlink -f ${BASH_SOURCE[0]})")" && pwd -P)" || exit 2

# ADD to the PATH the bin folder with all the pg and other deps scripts
export PATH="$(pwd)/../bin:$PATH"

# Mostly (If not only) when compiling the node package. (postgres)
export LD_LIBRARY_PATH="$(pwd)/../lib:$LD_LIBRARY_PATH"

export PM2_HOME="$(pwd)/../.pm2"

cd "$OLDPATH"

export GC="$(tput setaf 2)√$(tput sgr0)"
export RX="$(tput setaf 1)X$(tput sgr0)"