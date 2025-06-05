#!/usr/bin/env bash

decimal_to_hex() {
    if [[ $# -eq 0 ]]; then
        printf "0x0"
    fi

    printf "0x%x" "$1"
}

FEE_POSITION_PUBLIC_KEY="0x4313efb47c1e488ad57e9b66ff11a941310e23307d8fdbc26b2795199bcb57a"
LIQUIDATION_FUND_PUBLIC_KEY="0x4313efb47c1e488ad57e9b66ff11a941310e23307d8fdbc26b2795199bcb57a"
GOVERNANCE_ADMIN_ADDRESS="0x19ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
UPDATE_DELAY_SECONDS=$(decimal_to_hex 0)
COLLATERAL_ID="0x31857064564ed0ff978e687456963cba09c2c6985d8f9300a1de4962fafa054"
COLLATERAL_CONTRACT_ADDRESS="0x5ba91db44b3e6a4485b5dbfcb17d791faa9cb6890a42731b66b3536b28b8ed5"
COLLATERAL_QUANTUM=$(decimal_to_hex 1)
MAX_PRICE_INTERVAL=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
MAX_ORACLE_PRICE_VALIDITY=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
MAX_FUNDING_INTERVAL=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
MAX_FUNDING_RATE=$(decimal_to_hex 4294967295)
CANCEL_DELAY=$(decimal_to_hex $( expr 7 \* 24 \* 60 \* 60 ))
RPC="https://starknet-sepolia.public.blastapi.io/rpc/v0_8"

echo "FEE_POSITION_PUBLIC_KEY: ${FEE_POSITION_PUBLIC_KEY}"
echo "LIQUIDATION_FUND_PUBLIC_KEY: ${LIQUIDATION_FUND_PUBLIC_KEY}"
echo "GOVERNANCE_ADMIN_ADDRESS: ${GOVERNANCE_ADMIN_ADDRESS}"
echo "UPDATE_DELAY_SECONDS: ${UPDATE_DELAY_SECONDS}"
echo "COLLATERAL_ID: ${COLLATERAL_ID}"
echo "COLLATERAL_CONTRACT_ADDRESS: ${COLLATERAL_CONTRACT_ADDRESS}"
echo "COLLATERAL_QUANTUM: ${COLLATERAL_QUANTUM}"
echo "MAX_PRICE_INTERVAL: ${MAX_PRICE_INTERVAL}"
echo "MAX_ORACLE_PRICE_VALIDITY: ${MAX_ORACLE_PRICE_VALIDITY}"
echo "MAX_FUNDING_RATE: ${MAX_FUNDING_RATE}"
echo "CANCEL_DELAY: ${CANCEL_DELAY}"
echo "RPC: ${RPC}"

# governance_admin: ContractAddress,
# upgrade_delay: u64,
# collateral_id: AssetId,
# collateral_token_address: ContractAddress,
# collateral_quantum: u64,
# max_price_interval: TimeDelta,
# max_oracle_price_validity: TimeDelta,
# max_funding_interval: TimeDelta,
# max_funding_rate: u32,
# cancel_delay: TimeDelta,
# fee_position_owner_public_key: PublicKey,
# insurance_fund_position_owner_public_key: PublicKey,

HASH=$(starkli declare --rpc "$RPC" -w target/dev/perpetuals_Core.contract_class.json  --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5)
ADDRESS=$(starkli deploy --rpc "$RPC" -w "$HASH" ${GOVERNANCE_ADMIN_ADDRESS} ${UPDATE_DELAY_SECONDS} ${COLLATERAL_ID} ${COLLATERAL_CONTRACT_ADDRESS} ${COLLATERAL_QUANTUM} ${MAX_PRICE_INTERVAL} ${MAX_ORACLE_PRICE_VALIDITY} ${MAX_FUNDING_INTERVAL} ${MAX_FUNDING_RATE} ${CANCEL_DELAY} ${FEE_POSITION_PUBLIC_KEY} ${LIQUIDATION_FUND_PUBLIC_KEY} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5)
echo Contract deployed at $ADDRESS

APP_ROLE_ADMIN_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
OPERATOR_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
UPGRADE_GOVERNOR_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
SECURITY_ADMIN_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
SECURITY_AGENT_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
APP_GOVERNOR_ADDRESS="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
echo "Registering roles..."


starkli invoke --rpc "$RPC" -w "$ADDRESS" register_app_role_admin ${APP_ROLE_ADMIN_ADDRESS} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
starkli invoke --rpc "$RPC" -w "$ADDRESS" register_operator ${OPERATOR_ADDRESS} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
starkli invoke --rpc "$RPC" -w "$ADDRESS" register_governance_admin ${GOVERNANCE_ADMIN_ADDRESS} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
starkli invoke --rpc "$RPC" -w "$ADDRESS" register_upgrade_governor ${UPGRADE_GOVERNOR_ADDRESS} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
starkli invoke --rpc "$RPC" -w "$ADDRESS" register_security_admin ${SECURITY_ADMIN_ADDRESS} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
starkli invoke --rpc "$RPC" -w "$ADDRESS" register_security_agent ${SECURITY_AGENT_ADDRESS} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
starkli invoke --rpc "$RPC" -w "$ADDRESS" register_app_governor ${APP_GOVERNOR_ADDRESS} --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5

# echo "Contract deployed and initialised at address: ${ADDRESS}"


# HASH=$(starkli declare -w target/dev/perpetuals_Core.contract_class.json  --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5)
# ADDRESS=0x04c9164cd493976c6ad3e4591c009ebfc40b5cbb5d394b635ff3ddd25636572d
# starkli invoke -w "$ADDRESS" add_new_implementation "${HASH}" 1 0 --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" replace_to "${HASH}" 1 0 --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5

