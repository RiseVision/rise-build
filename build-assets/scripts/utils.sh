#!/usr/bin/env bash

exec_cmd() {
    echo "-> $1"
    bash -c "$1"
}
