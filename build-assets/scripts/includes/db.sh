#!/usr/bin/env bash
# CONFIG_PATH and LOGS_DIR must be already defined


db_envs() {
    export DB_NAME="$(cat "$CONFIG_PATH" | jq -r ".db.database")"
    export DB_PORT="$(cat "$CONFIG_PATH" | jq -r ".db.port")"
    export DB_USER="$(cat "$CONFIG_PATH" | jq -r ".db.user")"
    export DB_PASS="$(cat "$CONFIG_PATH" | jq -r ".db.password")"
    export DB_DATA="$(pwd)/data/pg"
    export DB_PID_FILE="$(pwd)/data/pg/postmaster.pid"
    export DB_LOG_FILE="${LOGS_DIR}/pgsql.log"
    export DB_SNAPSHOT="blockchain.db.gz"
    export DB_DOWNLOAD=Y
}

db_pid() {
    local pid=$1
    local res=$(head -1 "$DB_PID_FILE")
    if [[ "$pid" ]]; then
        eval $pid="'$res'"
    else
        echo "$res"
    fi
}

db_running() {
    pgrep -x "postgres" > /dev/null 2>&1  && [ -e "$DB_PID_FILE" ]
    return $?
}

db_ensure() {
    WHAT="$1" # running, stopped
    if [ "$1" == "running" ] && ! db_running; then
        db_start
    elif [ "$1" == "stopped" ] && db_running; then
        db_stop
    fi
}

db_start() {
    if db_running ; then
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


db_stop() {
    if ! db_running; then
        echo "X DB is not running"
    else
        if pg_ctl -D "$DB_DATA" -l "$DB_LOG_FILE" stop >> "$SH_LOG_FILE" 2>&1; then
            echo "√ DB stopped".
        else
            echo "X Failed to stop DB"
        fi
    fi
}


db_reset() {
    rm -rf "$DB_DATA"
}

db_initialize() {
    START=0
    if db_running; then
        psql -ltAq | grep -q "^${DB_NAME}" >> "$SH_LOG_FILE" 2>&1
        START=$?
    else
        # Checking the data directory
        if [ ! "$(ls -A "$DB_DATA")" ]; then
            START="1"
        fi
    fi

    if [ "$START" -eq 1 ] ; then
        echo '... Initializing DB ...'
        rm -rf "$DB_DATA"
        mkdir "$DB_DATA"
        pg_ctl initdb -D "$DB_DATA" >> "$SH_LOG_FILE" 2>&1
        sleep 5
        db_start
        sleep 2
        dropuser --if-exists "$DB_USER"  >> "$SH_LOG_FILE" 2>&1
        createuser "$DB_USER"  >> "$SH_LOG_FILE" 2>&1
        if ! psql -qd postgres -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" >> "$SH_LOG_FILE" 2>&1; then
            echo "X Failed to create DB user."
            exit 1
        else
            echo "√ DB user created."
        fi

        # CREATE DB
        dropdb --if-exists "$DB_NAME" >> "$SH_LOG_FILE" 2>&1
        if ! createdb -O "$DB_USER" "$DB_NAME" >> "$SH_LOG_FILE" 2>&1; then
            echo "X Failed to create DB database."
            exit 1
        else
            echo "√ DB created."
        fi

        # STOP DB
        db_stop

    fi
}