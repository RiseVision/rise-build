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
        echo "X Backup is running"
    else
        echo "√ Previous backup is not running."
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

    echo "√ Backup performed. Height = ${BACKUP_HEIGHT}"
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
        node_ensure "running"
    elif [ "$1" == "db" ]; then
        db_ensure "running"
    elif [ "$1" == "redis" ]; then
        redis_ensure "running"
    elif [ "$1" == "all" ]; then
        node_ensure "running"
        db_ensure "running"
        redis_ensure "running"
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

        node_status

        ;;
    "logs")
        ;;
    "help")
        ;;
    "backup")
        do_backup
        ;;
    "restoreBackup")
        if is_backupping; then
            echo "X Backup in progress."
            exit 1
        fi
        BACKUP_FILE="./data/backups/latest"
        if [ "$2" != "" ]; then
            BACKUP_FILE="$2"
        fi
        if [ ! -e "$BACKUP_FILE" ]; then
            echo "X Backup file does not exist.";
            exit 1
        fi
        touch ./data/backups/backup.lock

        node_ensure stopped
        db_ensure running
        dropdb --if-exists "$DB_NAME"
        db_initialize

        gunzip -c "$BACKUP_FILE" | psql "$DB_NAME" >> /dev/null

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
        echo "√ Snapshot verified $(($(date +'%s') - $start))"

        # Delete peers table.
        psql -d "$TARGETDB" -c "delete from peers;" &> /dev/null

        # Vacuum db before dumping
        vacuumdb --analyze --full "$TARGETDB" &> /dev/null

        HEIGHT="$(psql -d "$TARGETDB" -t -c "select height from blocks order by height desc limit 1;" | xargs)"
        SNAP_PATH="./data/backups/snap_${HEIGHT}.gz"
        pg_dump -O "$TARGETDB" | gzip > "$SNAP_PATH"

        # Drop DB

        dropdb --if-exists "$TARGETDB"

        echo "√ Snapshot created in $(($(date +'%s') - $start)) secs -> $SNAP_PATH"
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
esac