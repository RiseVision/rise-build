#!/usr/bin/env bash
# NETWORK, CONFIG_PATH and LOGS_DIR must be already defined


node_envs() {
    export PM2_CONFIG="$(pwd)/etc/pm2-${NETWORK}.json"
    export PM2_APPNAME=$(cat "$PM2_CONFIG" | jq -r ".apps[0].name")
    export NODE_PORT="$(cat "$CONFIG_PATH" | jq -r ".port")"
    _init_node_pid
}

_init_node_pid() {
    PM2_PID="$( pm2 jlist |jq -r ".[] | select(.name == \"$PM2_APPNAME\").pm2_env.pm_pid_path" )"
    if [ "$PM2_PID" != "" ]; then
        export NODE_PID="$PM2_PID"
    else
        export NODE_PID=$(cat "$PM2_CONFIG" | jq -r ".apps[0].pid_file")
    fi
}

node_pid() {
    _init_node_pid
    local pid=$1
    local res=$(head -1 "$NODE_PID")
    if [[ "$pid" ]]; then
        eval $pid="'$res'"
    else
        echo "$res"
    fi
}

node_running() {
    _init_node_pid
    if  [ -f "$NODE_PID" ]; then
        return 0
    else
        return 1
    fi
}

node_ensure() {
    WHAT="$1" # running, stopped
    if [ "$1" == "running" ] && ! node_running; then
        node_start
    elif [ "$1" == "stopped" ] && node_running; then
        node_stop
    fi
}

node_start() {
    if node_running ; then
        echo "√ NODE is running."
    else
        if ! pm2 start "$PM2_CONFIG" >> "$SH_LOG_FILE" 2>&1; then
			echo "X Failed to start NODE."
			exit 1
		else
			echo "√ NODE started successfully."
		fi
    fi
}


node_stop() {
    if ! node_running; then
        echo "X NODE is not running"
    else
        pm2 delete "$PM2_CONFIG" >> "$SH_LOG_FILE"
        sleep 1
        if node_running; then
            echo "X Failed to stop node "
        else
            echo "√ NODE stopped successfully."
        fi
    fi
}

node_reset() {
    :
}

node_initialize() {
    :
}

node_status() {
    if node_running; then
        echo "√ NODE is running [$(node_pid)] - [H=$(curl -s http://localhost:${NODE_PORT}/api/blocks/getStatus | jq -r ".height")]"
    else
        echo "X NODE not running!"
    fi
}