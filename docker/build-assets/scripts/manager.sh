#!/usr/bin/env bash

if [[ $EUID -eq 0 ]]; then
    echo "$RX This script should not be run using sudo or as the root user"
    exit 1
fi

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
        NETWORK="testnet"
    else
        echo "$RX Network is invalid. Restart the script to reset."
        rm ${NETWORK_FILE}
        exit 2
    fi
    CONFIG_PATH="$(pwd)/src/etc/${NETWORK}/config.json"
	LOGS_DIR="$(pwd)/logs"
    SH_LOG_FILE="$LOGS_DIR/shell.out"
    NUM_DELEGATES=101

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
    setup_cron

    if [ ! -f ./etc/node_config.json ]; then
        cat <<< '{
  "fileLogLevel": "error",
  "forging": {
    "secret": []
  }
}' > ./etc/node_config.json
        echo "$GC Created node-config file.."
   fi


}

first_init() {
    db_ensure "stopped"
    redis_ensure "stopped"
    node_ensure "stopped"

    db_reset
    redis_reset
    node_reset
}
is_backupping() {
    [ -f ./data/backups/backup.lock ]
}
do_backup() {
    node_ensure stopped
    db_ensure running
    mkdir -p ./data/backups
    if is_backupping; then
        echo "$RX Backup is running"
    else
        echo "$GC Previous backup is not running."
    fi
    # Create lock file.
    touch ./data/backups/backup.lock

    TARGETDB="${DB_NAME}_snap"
    dropdb --if-exists "$TARGETDB" &> /dev/null
    exit_if_prevfail "Cannot drop ${TARGETDB}"

    vacuumdb --analyze --full "$DB_NAME" &> /dev/null
    exit_if_prevfail "Cannot vacuum ${DB_NAME}"

    createdb "$TARGETDB" &> /dev/null
    exit_if_prevfail "Cannot createdb ${TARGETDB}"

    pg_dump "$DB_NAME" | psql "$TARGETDB" &> /dev/null
    exit_if_prevfail "Cannot copy ${DB_NAME} to ${TARGETDB}"

    node_ensure running
    BACKUP_HEIGHT=$(psql -d "$TARGETDB" -t -c 'select height from blocks order by height desc limit 1;' | xargs)
    BACKUP_NAME="./backup_${DB_NAME}_${BACKUP_HEIGHT}.gz"
    BACKUP_PATH="./data/backups/${BACKUP_NAME}"
    pg_dump -O "$TARGETDB" | gzip > ./data/backups/backup_${DB_NAME}_${BACKUP_HEIGHT}.gz

    rm ./data/backups/latest > /dev/null
    ln -s "$BACKUP_NAME" "./data/backups/latest"
    rm ./data/backups/backup.lock

    echo "$GC Backup performed. Height = ${BACKUP_HEIGHT}"
}

do_help() {
    echo "Help for manager.sh:"
    echo -e "\tstart (what)            | Starts service. What can be node, pg, redis, all"
    echo -e "\tstop (what)             | Stops service. What can be node, pg, redis, all"
    echo -e "\tstatus                  | Print services status and pids"
    echo -e "\tbackup                  | Perform a database backup"
    echo -e "\trestoreBackup [file]    | Restore a database backup (uses latest if no file is provided)"

    echo -e "\n** Advanced commands **"

    echo -e "\treset                   | Stops and resets data."
    echo -e "\tperformSnapshot         | Performs an optimized database snapshot with validation"
    echo -e "\tlogRotate               | Performs log rotation"

}

setup_cron() {
    local cmd="crontab"
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "$RX crontab not found"
        return 1
    fi
    crontab=$($cmd -l 2> /dev/null | sed '/#managed_rise/d' 2> /dev/null)

	crontab=$(cat <<-EOF
		$crontab
		@reboot $(command -v "bash") $(pwd)/manager.sh start all > ${LOGS_DIR}/cron.log 2>&1 #managed_rise
		@daily $(command -v "bash") $(pwd)/manager.sh logRotate > ${LOGS_DIR}/cron.log 2>&1 #managed_rise
EOF
	)

    oldcrontab=$($cmd -l 2> /dev/null)

    if [ "$oldcrontab" == "$crontab" ]; then
        return 0
    fi

	if ! printf "%s\n" "$crontab" | $cmd - >> "$SH_LOG_FILE" 2>&1; then
		echo "$RX Failed to update crontab."
		return 1
	else
		echo "$GC Crontab updated successfully."
		return 0
	fi
}


handle_start() {
    if [ "$1" == "node" ]; then
        node_ensure "running"
    elif [ "$1" == "db" ]; then
        db_ensure "running"
    elif [ "$1" == "redis" ]; then
        redis_ensure "running"
    elif [ "$1" == "all" ]; then
        db_ensure "running"
        redis_ensure "running"
        node_ensure "running"
    else
        echo "Please specify ${COMMAND} node or ${COMMAND} db or ${COMMAND} redis"
        exit 2
    fi
}


handle_stop() {
    if [ "$1" == "node" ]; then
        node_ensure "stopped"
    elif [ "$1" == "db" ]; then
        db_ensure "stopped"
    elif [ "$1" == "redis" ]; then
        redis_ensure "stopped"
    elif [ "$1" == "all" ]; then
        node_ensure "stopped"
        db_ensure "stopped"
        redis_ensure "stopped"
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
    "start")
        handle_start $2
        ;;
    "stop")
        handle_stop $2
        ;;
    "status")
        if db_running; then
            echo "$GC DB is running [$(db_pid)]"
        else
            echo "$RX DB not running!"
        fi
        if redis_running; then
            echo "$GC Redis is running [$(redis_pid)]"
        else
            echo "$RX Redis not running!"
        fi

        node_status

        ;;
    "help")
        do_help
        ;;
    "backup")
        do_backup
        ;;
    "restoreBackup")
        if is_backupping; then
            echo "$RX Backup in progress."
            exit 1
        fi
        BACKUP_FILE="./data/backups/latest"
        if [ "$2" != "" ]; then
            BACKUP_FILE="$2"
        fi
        if [ ! -e "$BACKUP_FILE" ]; then
            echo "$RX Backup file does not exist.";
            exit 1
        fi
        mkdir -p ./data/backups
        touch ./data/backups/backup.lock

        node_ensure stopped
        db_ensure running
        dropdb --if-exists "$DB_NAME"
        db_initialize
        db_ensure running

        sleep 5
        gunzip -c "$BACKUP_FILE" | psql -U "$DB_USER" "$DB_NAME" >> /dev/null 2>&1

        node_ensure running
        rm ./data/backups/backup.lock
        ;;
    "performSnapshot")
        # perform backup
        do_backup
        BACKUP_HEIGHT=$(basename $(readlink -f ./data/backups/latest) | rev | cut -d '_' -f 1 | cut -d '.' -f 2 | rev)

        TARGETDB="${DB_NAME}_snap"
        dropdb --if-exists "$TARGETDB" &> /dev/null
        exit_if_prevfail "Cannot drop ${TARGETDB}"

        createdb -O "$DB_USER" "$TARGETDB"  &> /dev/null
        exit_if_prevfail "Cannot createdb ${TARGETDB}"
        export PGPASSWORD="$DB_PASS"
        gunzip -c ./data/backups/latest | psql -U "$DB_USER" "$TARGETDB" >> /dev/null 2>&1
        exit_if_prevfail "Cannot import db to snapshot DB"

        # run node in snapshot verification mode.
        cd ./src/
        node ./dist/app.js -n "$NETWORK" -s -o "\$.db.database=$TARGETDB"  > ../logs/snapshot.log 2>&1 & THEPID=$!
        cd ..

        start=$(date +'%s')
        echo "Snapshot verification in process..."
        wait $THEPID
        exit_if_prevfail "Failed to verify snapshot"
        echo "$GC Snapshot verified $(($(date +'%s') - $start))"

        # Delete peers table.
        psql -d "$TARGETDB" -c "delete from peers;" &> /dev/null

        # Vacuum db before dumping
        vacuumdb --analyze --full "$TARGETDB" &> /dev/null

        HEIGHT="$(psql -d "$TARGETDB" -t -c "select height from blocks order by height desc limit 1;" | xargs)"
        SNAP_PATH="./data/backups/snap_${HEIGHT}.gz"
        pg_dump -O "$TARGETDB" | gzip > "$SNAP_PATH"

        # Drop DB

        dropdb --if-exists "$TARGETDB"

        echo "$GC Snapshot created in $(($(date +'%s') - $start)) secs -> $SNAP_PATH"
        ;;
    "reset")
        echo "This process will remove the database "
        read -r -n "Are you sure you want to proceed? (y/n): " YN

        if [ "$YN" != "y" ]; then
            echo "Goodbye."
            exit 0;
        fi

        db_ensure stop
        node_ensure stop
        redis_ensure stop

        db_reset
        redis_reset

        ;;
    "logRotate")
        logrotate ./etc/logrotate.conf
        ;;

    *)
        do_help
        ;;
esac