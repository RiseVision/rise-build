#!/usr/bin/env bash
# CONFIG_PATH and LOGS_DIR must be already defined


redis_envs() {
    export REDIS_CONFIG_FILE="$(pwd)/etc/redis.conf"
    export REDIS_PORT=$(cat "$CONFIG_PATH" | jq -r ".redis.port")
    export REDIS_PASSWORD=$(cat "$CONFIG_PATH" | jq -r ".redis.password")
    export REDIS_PID="$(pwd)/pids/redis.pid"
}

redis_reset() {
    rm -rf './data/redis'
    mkdir -p './data/redis'
}
redis_pid() {
    local pid=$1
    local res=$(head -1 "$REDIS_PID")
    if [[ "$pid" ]]; then
        eval $pid="'$res'"
    else
        echo "$res"
    fi
}

is_redis_system() {
    if [ "$REDIS_PORT" == '6379' ]; then
        return 0
    else
        return 1
    fi
}

redis_running() {
    if is_redis_system || [ -f "$REDIS_PID" ]; then
        return 0
    else
        return 1
    fi
}

redis_ensure() {
    WHAT="$1" # running, stopped
    if [ "$1" == "running" ] && ! redis_running; then
        redis_start
    elif [ "$1" == "stopped" ] && redis_running; then
        redis_stop
    fi
}

redis_start() {
    if redis_running ; then
        echo "√ Redis is running."
    else
        if ! redis-server "$REDIS_CONFIG_FILE" pidfile "$REDIS_PID" >> "$SH_LOG_FILE" 2>&1; then
			echo "X Failed to start Redis."
			exit 1
		else
			echo "√ Redis started successfully."
		fi
    fi
}


redis_stop() {
    if ! redis_running; then
        echo "X Redis is not running"
    else
        if is_redis_system; then
            echo "X Cannot stop OS Level Redis"
        else
            ## try with redis-cli
            if [ "$REDIS_PASSWORD" != "null" ]; then
                redis-cli -p "$REDIS_PORT" "-a $REDIS_PASSWORD" shutdown
            else
                redis-cli -p "$REDIS_PORT" shutdown
            fi

            sleep 1
            if redis_running; then
                echo "X Failed to stop redis through CLI. Force-stopping it"
                pkill -9 "$(head -1 $REDIS_PID)"
                echo "√ Redis-Server killed"
                rm $REDIS_PID
            else
                echo "√ Redis stopped"
            fi

        fi

    fi
}


redis_reset() {
    rm -rf "./data/redis"
}

redis_initialize() {
    mkdir -p "./data/redis"
}