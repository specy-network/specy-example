#!/usr/bin/env bash

set -o errexit
set -o pipefail
LOG_WARN()
{
    local content=${1}
    echo -e "\033[31m[WARN] ${content}\033[0m"
}

LOG_INFO()
{
    local content=${1}
    echo -e "\033[32m[INFO] ${content}\033[0m"
}
LOG_RESULT()
{
    local content=${1}
    echo -e "\033[33m[RESULT] ${content}\033[0m"
}

CLEANUP=${CLEANUP:-"0"}
NETWORK=${NETWORK:-"localnet"}
OS_PLATFORM=$(uname -s)
OS_ARCH=$(uname -m)
REGCHAIN_PLATFORM=${CHAIN_PLATFORM:-"linux_amd64"}
CHAIN_ID="specy"
CHAIN_BINARY=`which specyd`
FIREHOSE_COSMOS=`which firehose-cosmos`
LOG_INFO "chain path:$CHAIN_BINARY"
LOG_INFO "firehose-cosmos path:$FIREHOSE_COSMOS"
case $NETWORK in
  
  localnet)
    LOG_INFO "Using LOCALNET"
    CHAIN_GENESIS_HEIGHT=${CHAIN_GENESIS_HEIGHT:-"1"}
    MNEMONIC_1=${MNEMONIC_1:-"guard cream sadness conduct invite crumble clock pudding hole grit liar hotel maid produce squeeze return argue turtle know drive eight casino maze host"}
    MNEMONIC_2=${MNEMONIC_2:-"friend excite rough reopen cover wheel spoon convince island path clean monkey play snow number walnut pull lock shoot hurry dream divide concert discover"}
    MNEMONIC_3=${MNEMONIC_3:-"fuel obscure melt april direct second usual hair leave hobby beef bacon solid drum used law mercy worry fat super must ritual bring faculty"}
    GENESIS_COINS=${GENESIS_COINS:-"1000000000000000stake"}
  ;;
  *)
    LOG_WARN "Invalid network: $NETWORK"; exit 1;
  ;;
esac

case $OS_PLATFORM-$OS_ARCH in
  Darwin-x86_64) CHAIN_PLATFORM="darwin_amd64" ;;
  Darwin-arm64)  CHAIN_PLATFORM="darwin_arm64" ;;
  Linux-x86_64)  CHAIN_PLATFORM="linux_amd64"  ;;
  *) LOG_WARN "Invalid platform"; exit 1 ;;
esac

if [[ -z $(which "wget" || true) ]]; then
  echo "ERROR: wget is not installed"
  exit 1
fi

if [[ $CLEANUP -eq "1" ]]; then
  LOG_INFO "Deleting all local data"
  rm -rf ./tmp/ > /dev/null
fi

LOG_INFO "Setting up working directory"
mkdir -p tmp
pushd tmp

LOG_INFO "Your platform is $OS_PLATFORM/$OS_ARCH"

if [ ! -f $CHAIN_BINARY ]; then
  LOG_WARN "ERROR:dont exists CHAIN_BINARY "
  exit 1
fi

if [ ! -d "chain_home" ]; then
  LOG_INFO "Configuring home directory"
  $CHAIN_BINARY --home=chain_home init $(hostname) --chain-id $CHAIN_ID 2> /dev/null
fi

case $NETWORK in
  
  localnet) # Setup localnet
    LOG_INFO "Adding genesis accounts..."
    echo $MNEMONIC_1 | $CHAIN_BINARY --home chain_home keys add validator --recover --keyring-backend=test 
    echo $MNEMONIC_2 | $CHAIN_BINARY --home chain_home keys add user1 --recover --keyring-backend=test 
    echo $MNEMONIC_3 | $CHAIN_BINARY --home chain_home keys add user2 --recover --keyring-backend=test 
    $CHAIN_BINARY --home chain_home add-genesis-account $($CHAIN_BINARY --home chain_home keys show validator --keyring-backend test -a) $GENESIS_COINS
    $CHAIN_BINARY --home chain_home add-genesis-account $($CHAIN_BINARY --home chain_home keys show user1 --keyring-backend test -a) $GENESIS_COINS
    $CHAIN_BINARY --home chain_home add-genesis-account $($CHAIN_BINARY --home chain_home keys show user2 --keyring-backend test -a) $GENESIS_COINS

    LOG_INFO "Creating and collecting gentx..."
    $CHAIN_BINARY --home chain_home gentx validator 1000000000stake --chain-id $CHAIN_ID --keyring-backend test 
    $CHAIN_BINARY --home chain_home collect-gentxs
    
  ;;
esac

cat << END >> chain_home/config/config.toml

#######################################################
###       Extractor Configuration Options     ###
#######################################################
[extractor]
enabled = true
output_file = "stdout"
END

if [ ! -f "firehose.yml" ]; then
  cat << END >> firehose.yml
start:
  args:
    - ingestor
    - merger
    - firehose
  flags:
    common-first-streamable-block: $CHAIN_GENESIS_HEIGHT
    common-blockstream-addr: localhost:9000
    ingestor-mode: node
    ingestor-node-path: $CHAIN_BINARY
    ingestor-node-args: start --x-crisis-skip-assert-invariants --home=./chain_home
    ingestor-node-logs-filter: "module=(p2p|pex|consensus|x/bank)"
    firehose-real-time-tolerance: 99999h
    relayer-max-source-latency: 99999h
    verbose: 1
END
fi

