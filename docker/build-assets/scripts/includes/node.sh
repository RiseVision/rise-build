#!/usr/bin/env bash
# NETWORK, CONFIG_PATH and LOGS_DIR must be already defined


node_envs() {
    export PM2_CONFIG="$(pwd)/etc/pm2-${NETWORK}.json"
    export PM2_APPNAME=$(cat "$PM2_CONFIG" | jq -r ".apps[0].name")
    export NODE_PORT="$(cat "$CONFIG_PATH" | jq -r ".port")"
    _init_node_pid
}

_init_node_pid() {
    # Starts pm2 if not started already.
    pm2 jlist > /dev/null 2>&1
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
        node_start $2
    elif [ "$1" == "stopped" ] && node_running; then
        node_stop
    fi
}

node_start() {
    if node_running ; then
        echo "$GC NODE is running."
    else
        if ! pm2 start "$PM2_CONFIG"  >> "$SH_LOG_FILE" 2>&1; then
            echo "$RX Failed to start NODE."
            exit 1
        else
            echo "$GC NODE started successfully."
        fi
    fi
}


node_stop() {
    if ! node_running; then
        echo "$RX NODE is not running"
    else
        pm2 delete "$PM2_CONFIG" >> "$SH_LOG_FILE"
        sleep 1
        if node_running; then
            echo "$RX Failed to stop node "
        else
            echo "$GC NODE stopped successfully."
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
        local_nodeheight=`curl -s http://localhost:${NODE_PORT}/api/blocks/getStatus | jq -r '.height'`

        if [ "$NETWORK" == "mainnet" ]
        then
           network_nodeheight=`curl -s https://wallet.rise.vision/api/blocks/getStatus | jq -r '.height'`
        else
           network_nodeheight=`curl -s https://twallet.rise.vision/api/blocks/getStatus | jq -r '.height'`
        fi

        percent_sync=$((100*$local_nodeheight/$network_nodeheight))
        echo "$GC NODE is running [$(node_pid)] - [local Height:$local_nodeheight - Network Height:$network_nodeheight - Sync:$percent_sync%]"
    else
        echo "$RX NODE not running!"
    fi
}
