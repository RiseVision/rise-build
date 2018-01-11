#!/usr/bin/env bash

exec_cmd() {
    echo "-> $1"
    bash -c "$1"
}
exit_if_prevfail() {
    PREV=$?
    if [ ! "$PREV" -eq 0 ]; then
        echo "$1 - ${PREV}";
        exit 1;
    fi
}