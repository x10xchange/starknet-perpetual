#!/usr/bin/env bash

decimal_to_hex() {
    if [[ $# -eq 0 ]]; then
        printf "0x0"
    fi

    printf "0x%x" "$1"
}
while getopts "a:u:" opt
do
   case "$opt" in
      a ) account="$OPTARG" ;;
      u ) url="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done
if [ -z "$account" ]
then
   echo "Account is missing pass -a";
   helpFunction
fi
if [ -z "$url" ]
then
   echo "Url is missing pass -u";
   helpFunction
fi

# FEE_POSITION_PUBLIC_KEY="0x4313efb47c1e488ad57e9b66ff11a941310e23307d8fdbc26b2795199bcb57a"
# LIQUIDATION_FUND_PUBLIC_KEY="0x4313efb47c1e488ad57e9b66ff11a941310e23307d8fdbc26b2795199bcb57a"
# GOVERNANCE_ADMIN_ADDRESS="0x19ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
# UPDATE_DELAY_SECONDS=$(decimal_to_hex 0)
# COLLATERAL_ID="0x31857064564ed0ff978e687456963cba09c2c6985d8f9300a1de4962fafa054"
# COLLATERAL_CONTRACT_ADDRESS="0x5ba91db44b3e6a4485b5dbfcb17d791faa9cb6890a42731b66b3536b28b8ed5"
# COLLATERAL_QUANTUM=$(decimal_to_hex 1)
# MAX_PRICE_INTERVAL=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
# MAX_ORACLE_PRICE_VALIDITY=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
# MAX_FUNDING_INTERVAL=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
# MAX_FUNDING_RATE=$(decimal_to_hex 4294967295)
# CANCEL_DELAY=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
# RPC="https://starknet-sepolia.public.blastapi.io/rpc/v0_8"

# echo "FEE_POSITION_PUBLIC_KEY: ${FEE_POSITION_PUBLIC_KEY}"
# echo "LIQUIDATION_FUND_PUBLIC_KEY: ${LIQUIDATION_FUND_PUBLIC_KEY}"
# echo "GOVERNANCE_ADMIN_ADDRESS: ${GOVERNANCE_ADMIN_ADDRESS}"
# echo "UPDATE_DELAY_SECONDS: ${UPDATE_DELAY_SECONDS}"
# echo "COLLATERAL_ID: ${COLLATERAL_ID}"
# echo "COLLATERAL_CONTRACT_ADDRESS: ${COLLATERAL_CONTRACT_ADDRESS}"
# echo "COLLATERAL_QUANTUM: ${COLLATERAL_QUANTUM}"
# echo "MAX_PRICE_INTERVAL: ${MAX_PRICE_INTERVAL}"
# echo "MAX_ORACLE_PRICE_VALIDITY: ${MAX_ORACLE_PRICE_VALIDITY}"
# echo "MAX_FUNDING_RATE: ${MAX_FUNDING_RATE}"
# echo "CANCEL_DELAY: ${CANCEL_DELAY}"
# echo "RPC: ${RPC}"

# # governance_admin: ContractAddress,
# # upgrade_delay: u64,
# # collateral_id: AssetId,
# # collateral_token_address: ContractAddress,
# # collateral_quantum: u64,
# # max_price_interval: TimeDelta,
# # max_oracle_price_validity: TimeDelta,
# # max_funding_interval: TimeDelta,
# # max_funding_rate: u32,
# # cancel_delay: TimeDelta,
# # fee_position_owner_public_key: PublicKey,
# # insurance_fund_position_owner_public_key: PublicKey,
# pwd
# HASH=$(./onchain_deploy/declare.sh -a $account -u $url -c Core -p perpetuals)
# echo Hash is $HASH
# ADDRESS=$(sncast --account $account  deploy -u $url --class-hash=$HASH  --constructor-calldata ${GOVERNANCE_ADMIN_ADDRESS} ${UPDATE_DELAY_SECONDS} ${COLLATERAL_ID} ${COLLATERAL_CONTRACT_ADDRESS} ${COLLATERAL_QUANTUM} ${MAX_PRICE_INTERVAL} ${MAX_ORACLE_PRICE_VALIDITY} ${MAX_FUNDING_INTERVAL} ${MAX_FUNDING_RATE} ${CANCEL_DELAY} ${FEE_POSITION_PUBLIC_KEY} ${LIQUIDATION_FUND_PUBLIC_KEY} | grep -oE '0x[0-9a-f]{64}'| sed -n '1p')
# echo Contract deployed at $ADDRESS
# sleep 10

# APP_ROLE_ADMIN_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
# OPERATOR_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
# UPGRADE_GOVERNOR_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
# SECURITY_ADMIN_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
# SECURITY_AGENT_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
# APP_GOVERNOR_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
# echo "Registering roles..."

# sncast --account $account invoke -u $url --contract-address $ADDRESS --function register_app_role_admin --calldata  ${APP_ROLE_ADMIN_ADDRESS}
# sncast --account $account invoke -u $url --contract-address $ADDRESS --function register_operator --calldata  ${OPERATOR_ADDRESS}
# sncast --account $account invoke -u $url --contract-address $ADDRESS --function register_governance_admin --calldata  ${GOVERNANCE_ADMIN_ADDRESS}
# sncast --account $account invoke -u $url --contract-address $ADDRESS --function register_upgrade_governor --calldata  ${UPGRADE_GOVERNOR_ADDRESS}
# sncast --account $account invoke -u $url --contract-address $ADDRESS --function register_security_admin --calldata  ${SECURITY_ADMIN_ADDRESS}
# sncast --account $account invoke -u $url --contract-address $ADDRESS --function register_security_agent --calldata  ${SECURITY_AGENT_ADDRESS}
sncast --account $account invoke -u $url --contract-address 0x05F062C924EcD9f5d4C74c567A28cc5502332fcf21828687EC20581a03F7E1C8 --function register_app_governor --calldata  0x030c48A027CCcD0A89262Ac3a0E92973cE206B206160380200FD68FB19B80c88

#TRANSFER_COMPONENT_HASH=$(./onchain_deploy/declare.sh -a $account -u $url -c TransferManager -p perpetuals)
#echo "transfer hash $TRANSFER_COMPONENT_HASH"
#WITHDRAWAL_COMPONENT_HASH=$(./onchain_deploy/declare.sh -a $account -u $url -c WithdrawalManager -p perpetuals)
#echo "withdrawal hash $WITHDRAWAL_COMPONENT_HASH"
#LIQUIDATION_COMPONENT_HASH=$(./onchain_deploy/declare.sh -a $account -u $url -c LiquidationManager -p perpetuals)
#echo "liquidation hash $LIQUIDATION_COMPONENT_HASH"
#DELEVERAGE_COMPONENT_HASH=$(./onchain_deploy/declare.sh -a $account -u $url -c DeleverageManager -p perpetuals)
#echo "deleverage hash $DELEVERAGE_COMPONENT_HASH"
#DEPOSIT_COMPONENT_HASH=$(./onchain_deploy/declare.sh -a $account -u $url -c DepositManager -p perpetuals)
#echo "deposit hash $DEPOSIT_COMPONENT_HASH"
#./onchain_deploy/register.sh -a $account -u $url -c $ADDRESS -n TRANSFERS -h ${TRANSFER_COMPONENT_HASH}
#./onchain_deploy/register.sh -a $account -u $url -c $ADDRESS -n WITHDRAWALS -h ${WITHDRAWAL_COMPONENT_HASH}
#./onchain_deploy/register.sh -a $account -u $url -c $ADDRESS -n LIQUIDATIONS -h ${LIQUIDATION_COMPONENT_HASH}
#./onchain_deploy/register.sh -a $account -u $url -c $ADDRESS -n DELEVERAGES -h ${DELEVERAGE_COMPONENT_HASH}
#./onchain_deploy/register.sh -a $account -u $url -c $ADDRESS -n DEPOSITS -h ${DEPOSIT_COMPONENT_HASH}
#


# HASH=$(starkli declare -w target/dev/perpetuals_Core.contract_class.json  --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5)
# ADDRESS=0x04c9164cd493976c6ad3e4591c009ebfc40b5cbb5d394b635ff3ddd25636572d
# starkli invoke -w "$ADDRESS" add_new_implementation "${HASH}" 1 0 --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" replace_to "${HASH}" 1 0 --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5

