#!/usr/bin/env bash


cd "$(cd -P -- "$(dirname -- "$(readlink -f $0)")" && pwd -P)" || exit 2

# Import env_vars and utils
. "$(pwd)/env_vars.sh"
. "$(pwd)/utils.sh"
. "$(pwd)/includes/db.sh"
. "$(pwd)/includes/redis.sh"
. "$(pwd)/includes/node.sh"

# Switch to root directory.
cd ..


# Allocates variables for use later, reusable for changing pm2 config.
config() {
    NETWORK_FILE="$(pwd)/etc/.network"
    if [ ! -f "$NETWORK_FILE" ]; then
        [ "$NETWORK" ] || read -r -p "Which network do you want to run on? mainnet,testnet? (Default=mainnet): " NETWORK
        if [ "$NETWORK" == "mainnet" ] || [ "$NETWORK" == "" ]; then
            echo "mainnet" > ${NETWORK_FILE}
        elif [ "$NETWORK" == "testnet" ]; then
            echo "testnet" > ${NETWORK_FILE}
        else
            echo "Network is invalid"
            exit 2
        fi
    fi
    if [ "$(grep "mainnet" "${NETWORK_FILE}")" ]; then
        NETWORK="mainnet"
    elif [ "$(grep "testnet" "${NETWORK_FILE}")" ]; then
        NETWORK="mainnet"
    else
        echo "Network is invalid. Restart the script to reset."
        rm ${NETWORK_FILE}
        exit 2
    fi
    CONFIG_PATH="$(pwd)/src/etc/${NETWORK}/config.json"
	LOGS_DIR="$(pwd)/logs"
    SH_LOG_FILE="$LOGS_DIR/shell.out"
    exec > >(tee -ia "$SH_LOG_FILE")
    exec 2>&1

    # Calls submodule scripts envs.
    db_envs
    redis_envs
    node_envs
}

initialize_if_necessary() {
    db_initialize
    redis_initialize
    node_initialize
}

first_init() {
    db_ensure "stopped"
    redis_ensure "stopped"
    node_ensure "stopped"

    db_reset
    redis_reset
    node_reset
}

setup_cron() {
    local cmd="crontab"
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "X crontab not found"
        return 1
    fi
    	crontab=$($cmd -l 2> /dev/null | sed '/lisk\.sh start/d' 2> /dev/null)

	crontab=$(cat <<-EOF
		$crontab
		@reboot $(command -v "bash") $(pwd)/manager.sh start > ${LOGS_DIR}/cron.log 2>&1
EOF
	)

	if ! printf "%s\n" "$crontab" | $cmd - >> "$SH_LOG_FILE" 2>&1; then
		echo "X Failed to update crontab."
		return 1
	else
		echo "√ Crontab updated successfully."
		return 0
	fi
}


handle_start() {
    if [ "$1" == "node" ]; then
        node_start
    elif [ "$1" == "db" ]; then
        db_start
    elif [ "$1" == "redis" ]; then
        redis_start
    else
        echo "Please specify ${COMMAND} node or ${COMMAND} db or ${COMMAND} redis"
        exit 2
    fi
}


handle_stop() {
    if [ "$1" == "node" ]; then
        node_stop
    elif [ "$1" == "db" ]; then
        db_stop
    elif [ "$1" == "redis" ]; then
        redis_stop
    else
        echo "Please specify ${COMMAND} node or ${COMMAND} db or ${COMMAND} redis"
        exit 2
    fi
}
# CREATE env vars.
config
initialize_if_necessary

COMMAND="$1"

case $1 in
    "reset")
        db_ensure "stopped"
        db_reset

        ;;
    "start")
        handle_start $2
        ;;
    "stop")
        handle_stop $2
        ;;
    "status")
        if db_running; then
            echo "√ DB is running [$(db_pid)]"
        else
            echo "X DB not running!"
        fi
        if redis_running; then
            echo "√ Redis is running [$(redis_pid)]"
        else
            echo "X Redis not running!"
        fi
        if node_running; then
            echo "√ NODE is running [$(node_pid)]"
        else
            echo "X NODE not running!"
        fi
        ;;
    "logs")
        ;;
    "help")
        ;;
    "backup")
        db_ensure stopped
        node_ensure stopped
        redis_ensure stopped

        ;;
esac