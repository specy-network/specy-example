#!/bin/bash

graphnode_data_path="./graphnode-data"
deploy_home_dir=$(pwd)
#if debug is true ,the gov voting period time will be set to "180s"
debug=true
LOG_ERROR="ERROR"
LOG_WARNING="WARNING"
LOG_SUCCESS="SUCCESS"
CHAIN_ID="specy"
CHAIN_BINARY="specyd"
CHAIN_HOME="./tmp/chain_home"
help() {
    cat << EOF
Usage:
  
    -clean <Clean chain data>
    -check <Env check >
    -deploy <Deploy chain>          
    -graphnode <Start graph node>   
    -manifest <Deploy system manifest to graph node >
    -transfer <transfer test (after system proposal passed)>
    -deploy_manifest <deploy graphnode manifest>
    -help <Help>
EOF
exit 0
}



parse_params()
{
    case $1 in 
        clean) clean
        ;;
        deploy) deploy_chain 
        ;;
        check) check_env
        ;;
        graphnode) deploy_graph_node
        ;;
        manifest) deploy_system_manifest
        ;;
        create_task) create_task
        ;;
        set_reward_list) set_reward_list
        ;;
        help) help
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

        # select graph-node tmux session 
        if tmux has-session -t regchain-node 2>/dev/null; then
            # if exsist ,kill it
            log $LOG_SUCCESS "kill tmux regchain-node session"
            tmux kill-session -t regchain-node
        else
            # if is not exisis 
            log $LOG_SUCCESS "Tmux session regchain-node does not exist"
        fi

        log "start remove chain data."
        chain_work_path='./tmp'
        if [ -d "$chain_work_path" ]; then
            rm -rf "$chain_work_path"
        else
            log $LOG_WARNING "$chain_work_path does not exist."
        fi

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
        rm -rf './logs/regchain.log'
        rm -rf './logs/graphnode.log'

        log $LOG_SUCCESS "clean end"

    elif [[ "$answer" == "n" ]]; then
        log "Exiting..."
    else
        log $LOG_ERROR "Invalid input. Please enter 'y' or 'n'."
    
    fi

    
}

check_env(){
    log "===========================CHECK ENV==================================="
    log "check chain binary env......"
    specyd version > /dev/null
        if [ $? -eq  0 ]; then
            log $LOG_SUCCESS "chain binary already installed!"
        else
            log $LOG_ERROR "chain binary is not install"
            exit
        fi
    log "check firehose-cosmos env......"
    firehose-cosmos --version > /dev/null
        if [ $? -eq  0 ]; then
            log $LOG_SUCCESS  "firehose-cosmos already installed!"
        else
            log $LOG_ERROR "firehose-cosmos is not install"
            exit
        fi
    log "check graph-node env......"
    graph-node --version > /dev/null
        if [ $? -eq  0 ]; then
            log $LOG_SUCCESS  "graph-node already installed!"
        else
            log $LOG_ERROR "graph-node is not install"
            exit
        fi
    log "check docker env......"
    docker -v > /dev/null
        if [ $? -eq  0 ]; then
            log $LOG_SUCCESS  "docker already installed!"
        else
            log $LOG_ERROR "docker is not install"
            exit
        fi

    log "check docker-compose env......"
    docker-compose -v > /dev/null
        if [ $? -eq  0 ]; then
            log $LOG_SUCCESS  "docker-compose already installed!"
        else
            log $LOG_ERROR "docker-compose is not install"
            exit
        fi 

    log "check nodejs env......"
    node --version > /dev/null
        if [ $? -eq  0 ]; then
            log $LOG_SUCCESS  "node is alredy installed!"
        else
            log $LOG_ERROR "nodejs is not install"
            exit
        fi
    log "checkout node version and install yarn"
    npm --version > /dev/null
        if [ $? -eq  0 ]; then
            log $LOG_SUCCESS  "npm is alredy installed!"
        else
            log $LOG_ERROR "npm is not install"
            exit
        fi
    node_version=$(node -v)
    required_version="v16.0.0"
    if version_compare $node_version  $required_version; then
        log $LOG_SUCCESS  "node version is up to date"
    else
        log $LOG_ERROR "node verison need GE 16.0.0"
        exit
    fi
    if npm list -g --depth=0 yarn >/dev/null 2>&1; then
        log $LOG_SUCCESS "yarn is already installed globally"
    else
        log $LOG_ERROR "yarn not installed"
        exit
    fi
    log "=============================================================="
}

deploy_chain(){
    # firstly check env
    check_env
    log $LOG_SUCCESS "Passed env check!" 
    log "Generate chain config file and user info."
    bash "./scripts/bootstrap.sh"
    

    # Check if tmux is installed
    if dpkg -s tmux >/dev/null 2>&1; then
        log $LOG_SUCCESS "tmux is already installed."
    else
    # Install tmux if it is not installed
        log $LOG_WARN "tmux is not installed. Installing..."
        sudo apt-get install tmux -y
    fi
    # Start a new tmux session and detach it
    tmux new-session -d -s chain-node

    # Create a new window and run a command in it
    tmux new-window -t chain-node:1 -n "chain-node window"
    tmux send-keys -t chain-node:1 "bash './scripts/start.sh' >> ./logs/firehose.log " C-m

    log $LOG_SUCCESS "View the background node program through the command ' tmux attach -t regchain-node '"
    log $LOG_SUCCESS "You can also view the background node program at View logs in ./logs/regchain/logs"
    log $LOG_SUCCESS "Regchain network deploy success! Please wait for 10 minutes to deploy the graphnode service"
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
}
deploy_system_manifest(){
    log "deploy system graph node manifest"
    cd "../manifests/system-manifest"
    yarn 
    yarn codegen && yarn build
    yarn create-local && yarn deploy-local
    cd $deploy_home_dir

    cd "../manifests/ics721-manifest"
    yarn 
    yarn codegen && yarn build
    yarn create-local && yarn deploy-local
    cd $deploy_home_dir
    log "End of deployment manifest. Please review the information to determine whether the deployment succeeded or failed "


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
    $CHAIN_BINARY tx specy create-task \
        rewards SetRewards \
        "{\"params\":[\"1686553200\",\"a7dc6c23c3d0e2f14587f2096071858c0d52957d8a2117e5dd4ada522fa742cf\"],\"index\":1}" \
        true "fsadfsafdsafdsafsaf" \
        --chain-id $CHAIN_ID \
        --from $($CHAIN_BINARY --home $CHAIN_HOME keys show validator --keyring-backend test -a) \
        --keyring-backend test \
        --home $CHAIN_HOME \
        --yes
}

set_reward_list(){
    $CHAIN_BINARY tx rewards set-reward-list \
        token1,token2 \
        --chain-id $CHAIN_ID \
        --from $($CHAIN_BINARY --home $CHAIN_HOME keys show validator --keyring-backend test -a) \
        --keyring-backend test \
        --home $CHAIN_HOME \
        --yes
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
