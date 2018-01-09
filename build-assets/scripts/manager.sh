#!/usr/bin/env bash


cd "$(cd -P -- "$(dirname -- "$0")" && pwd -P)" || exit 2

# Import env_vars and utils
. "$(pwd)/env_vars.sh"
. "$(pwd)/utils.sh"


# Allocates variables for use later, reusable for changing pm2 config.
config() {
    NETWORK_FILE="$(pwd)/../etc/.network"
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
    CONFIG_PATH="$(pwd)/../src/etc/${NETWORK}/config.json"
	DB_NAME="$(cat "$CONFIG_PATH" | jq -r ".db")"
	DB_PORT="$(cat "$CONFIG_PATH" | jq -r ".db.port")"
	DB_USER="$(cat "$CONFIG_PATH" | jq -r ".db.user")"
	DB_PASS="$(cat "$CONFIG_PATH" | jq -r ".db.password")"
	DB_DATA="$(pwd)/../data/pg"
	LOGS_DIR="$(pwd)/../logs"
	DB_LOG_FILE="${LOGS_DIR}/pgsql.log"
	DB_SNAPSHOT="blockchain.db.gz"
	DB_DOWNLOAD=Y

    # Setup logging
    SH_LOG_FILE="$LOGS_DIR/shell.out"
    exec > >(tee -ia "$SH_LOG_FILE")
    exec 2>&1
}

first_init() {
    rm -rf "$DB_DATA"
    pg_ctl initdb -D "$DB_DATA" >> "$SH_LOG_FILE" 2>&1
    sleep 5
    start_db
    sleep 2

    ## CREATE USER

    dropuser --if-exists "$DB_USER"  >> "$SH_LOG_FILE" 2>&1
    createuser "$DB_USER"  >> "$SH_LOG_FILE" 2>&1
    if ! psql -qd postgres -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" >> "$SH_LOG_FILE" 2>&1; then
		echo "X Failed to create DB user."
		exit 1
	else
		echo "√ DB user created successfully."
	fi

    # CREATE DB
    dropdb --if-exists "$DB_NAME" >> "$SH_LOG_FILE" 2>&1
    if ! createdb -O "$DB_USER" "$DB_NAME" >> "$SH_LOG_FILE" 2>&1; then
		echo "X Failed to create DB database."
		exit 1
	else
		echo "√ DB database created successfully."
	fi
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


start_db() {
    if pgrep -x "postgres" > /dev/null 2>&1; then
        echo "√ DB is running."
    else
        if ! pg_ctl -D "$DB_DATA" -l "$DB_LOG_FILE" start >> "$SH_LOG_FILE" 2>&1; then
			echo "X Failed to start DB."
			exit 1
		else
			echo "√ DB started successfully."
		fi
    fi
}

handle_start() {
    if [ "$1" == "node" ]; then
        start_node
    elif [ "$1" == "db" ]; then
        start_db
    else
        echo "Please specify ${COMMAND} node or ${COMMAND} db"
        exit 2
    fi
}


# CREATE env vars.
config


COMMAND="$1"

case $1 in
    "start")
        handle_start $2
        ;;
    "stop")
        ;;
    "status")
        ;;
    "logs")
        ;;
    "help")
        ;;
    "backup")
        ;;
esac