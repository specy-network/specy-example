#!/bin/bash

graphnode_data_path="./graphnode-data"
deploy_home_dir=$(pwd)
#if debug is true ,the gov voting period time will be set to "180s"
debug=true
LOG_ERROR="ERROR"
LOG_WARNING="WARNING"
LOG_SUCCESS="SUCCESS"
CHAIN_ID="ibc-2"
CHAIN_BINARY=`which iris`
help() {
    cat << EOF
Usage:
  
    -clean <Clean chain data>       
    -graphnode <Start graph node>   
    -manifest <Deploy system manifest to graph node >
    -issue <issue nft denom>
    -mint <mint nft token>
    -ibc-nft-transfer <ibc nft transfer>
    -help <Help>
EOF
exit 0
}

issue_nft_denom()
{
    iris tx nft issue class222  --name=class222 --from=$($CHAIN_BINARY  --home ./data/ibc-1 keys show validator --keyring-backend test -a) \
     --mint-restricted=false --update-restricted=false --chain-id=ibc-1 \
     --keyring-backend=test --home=./data/ibc-1 \
     --node=tcp://localhost:26557
}

mint_nft_token()
{
    iris tx nft mint class222 token222 --recipient=$($CHAIN_BINARY  --home ./data/ibc-1 keys show validator --keyring-backend test -a)  \
    --from=$($CHAIN_BINARY  --home ./data/ibc-1 keys show validator --keyring-backend test -a)  --chain-id=ibc-1 --keyring-backend=test \
    --home=./data/ibc-1 --node=tcp://0.0.0.0:26557
}

ibc_nft_transfer()
{
    iris tx nft-transfer transfer nft-transfer channel-0 $($CHAIN_BINARY  --home ./data/ibc-2 keys show validator --keyring-backend test -a) \
    class222 token222 --from=$($CHAIN_BINARY  --home ./data/ibc-1 keys show validator --keyring-backend test -a)  --chain-id=ibc-1 \
    --keyring-backend=test --home=./data/ibc-1 --node=tcp://0.0.0.0:26557
}

create_executor(){
    iris tx specy create-executor 10000uiris "iasreport info" "enclave pk info" \
    --from $($CHAIN_BINARY --home ./data/ibc-2 keys show validator --keyring-backend test -a) \
        --keyring-backend test \
        --gas auto \
        --chain-id $CHAIN_ID \
        --home ./data/ibc-2 

}

create_task(){
    iris tx specy create-task \
    rewards SetRewards \
    "{\"params\":[\"dasdasdasdasdasdasda\",\"merkelrootdsdadsadadsada\"],\"index\":1}" \
    true "fsadfsafdsafdsafsaf" \
    --from $($CHAIN_BINARY --home ./data/ibc-2 keys show validator --keyring-backend test -a) \
        --keyring-backend test \
        --gas auto \
        --chain-id $CHAIN_ID \
        --home ./data/ibc-2 
}

execute_task(){
    specyd tx specy execute-task \
$1 \
"{\"params\":[\"dasdasdasdasdasdasda\",\"merkelrootdsdadsadadsada\"],\"index\":1}" \
--from $($CHAIN_BINARY --home ./data/ibc-2 keys show validator --keyring-backend test -a) \
        --keyring-backend test \
        --gas auto \
        --chain-id $CHAIN_ID \
        --home ./data/ibc-2 
}



parse_params()
{
    case $1 in 
        clean) clean
        ;;
        graphnode) deploy_graph_node
        ;;
        manifest) deploy_system_manifest
        ;;
        help) help
        ;;
        issue) issue_nft_denom
        ;;
        mint) mint_nft_token
        ;;
        ibc-nft-transfer) ibc_nft_transfer
        ;;
        create-executor) create_executor
        ;;
        create-task) create_task
        ;;
        execute-task) execute_task
        ;;
    esac
}



clean(){
    read -p "Do you want to remove chain network and delete data? (y/n) " answer
    if [[ "$answer" == "y" ]]; then
        log "start remove graphnode and regchain node ."
            # select graph-node tmux session 
        if tmux has-session -t graphnode 2>/dev/null; then
            # if exsist ,kill it
            log $LOG_SUCCESS "kill tmux graphnoe session"
            tmux kill-session -t graphnode
        else
            # if is not exisis 
            log $LOG_SUCCESS "Tmux session graphnode does not exist"
        fi
        killall firehose-cosmos


        log "start remove graphnode data."
        cd $graphnode_data_path
        if [ ! -d "docker-compose.yml" ]; then
            docker-compose down
        fi

        graphnode_data_save_path='./data'
        if [ -d "$graphnode_data_save_path" ]; then
            rm -rf "$graphnode_data_save_path"
        else
            log $LOG_WARNING "$graphnode_data_save_path does not exist."
        fi
        cd $deploy_home_dir
        log "start remove logs ."
        rm -rf './logs/firehose.log'
        rm -rf './logs/graphnode.log'

        log $LOG_SUCCESS "clean end"

    elif [[ "$answer" == "n" ]]; then
        log "Exiting..."
    else
        log $LOG_ERROR "Invalid input. Please enter 'y' or 'n'."
    
    fi

    
}

deploy_ipfs_postgresql(){
    cd $graphnode_data_path
    log "deploy ipfs and postgresql docker  container..."
    docker-compose up -d 
    sleep 5
    ipfs_container_status=$(docker inspect --format '{{.State.Status}}' graphnode-data-ipfs-1)

    if [ "$ipfs_container_status" = "running" ]; then
        log $LOG_SUCCESS  "Ipfs container is running"
    else
        log $LOG_WARNING "Ipfs container is not running"
        exit  
    fi
    postgres_container_status=$(docker inspect --format '{{.State.Status}}' graphnode-data-postgres-1)
    if [ "$postgres_container_status" = "running" ]; then
        log $LOG_SUCCESS  "postgres container is running"
    else
        log $LOG_WARNING "postgres container is not running"
        exit  
    fi
    cd $deploy_home_dir
}

deploy_graph_node(){
    
    log "Start ipfs and postgresql."
    deploy_ipfs_postgresql
    sleep 10

    # Start a new tmux session and detach it
    tmux new-session -d -s graphnode

    # Create a new window and run a command in it
    tmux new-window -t graphnode:1 -n "graphnode window"
    tmux send-keys -t graphnode:1 "graph-node --config ./source/graphnode/config.toml --ipfs 127.0.0.1:5001 --node-id index_node_cosmos_1 &> ./logs/graphnode.log " C-m

    log $LOG_SUCCESS "View the background graphnode node program through the command ' tmux attach -t graphnode-node '"
    log $LOG_SUCCESS "Graphnode deploy success! "

    sleep 10

    log "Start deploy manifest"

    deploy_system_manifest

    
}
deploy_system_manifest(){
    log "deploy system graph node manifest"
    cd "../manifests/ics721-manifest"
    yarn 
    yarn codegen && yarn build
    yarn create-local && yarn deploy-local
    cd $deploy_home_dir
    log "End of deployment manifest. Please review the information to determine whether the deployment succeeded or failed "
}



dir_must_exists() {
    if [ ! -d "$1" ]; then
        exit_with_clean "$1 DIR does not exist, please check!"
    fi
}
exit_with_clean()
{
    local content=${1}
    echo -e "\033[31m[ERROR] ${content}\033[0m"
    if [ -d "${chain_deploy_path}" ];then
       rm -rf ${chain_deploy_path}
    fi
    exit 1
}
log() {
  # Define colors
  local RESET='\033[0m'
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  
  # Get the current date and time
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  # Get the current line number
  local line_num=${BASH_LINENO[0]}

  # Print the log message with timestamp and line number, and color based on the log level
  if [ "$1" == "ERROR" ]; then
    echo -e "${RED}$timestamp [Line $line_num] [ERROR]: $2${RESET}"
  elif [ "$1" == "WARNING" ]; then
    echo -e "${YELLOW}$timestamp [Line $line_num] [WARNING]: $2${RESET}"
  elif [ "$1" == "SUCCESS" ]; then
    echo -e "${GREEN}$timestamp [Line $line_num] [SUCCESS]: $2${RESET}"
  else
    echo -e "${RESET}$timestamp [Line $line_num]: $1${RESET}"
  fi
}
version_compare() {
    # Remove 'v' character from version strings
    local ver1="${1#v}"
    local ver2="${2#v}"
    
    if dpkg --compare-versions "$ver1" ge "$ver2"; then
        return 0
    else
        return 1
    fi
}
parse_params $@
