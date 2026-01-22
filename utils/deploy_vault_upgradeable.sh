#!/bin/bash

decimal_to_hex() {
    if [[ $# -eq 0 ]]; then
        printf "0x0"
    fi

    printf "0x%x" "$1"
}

str_to_felt_array() {
    echo "0x0" "$(echo 0x$(echo -n $1 | xxd -p ))"  "$(decimal_to_hex ${#1})"
}

helpFunction()
{
   echo ""
   echo "Usage: $0 -a Account name -u RpcUrl -c contract -p package"
   exit 1 # Exit script after printing help
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


NAME=$(str_to_felt_array "XVS")
SYMBOL=$(str_to_felt_array "XVS")
COLLATERAL_CONTRACT_ADDRESS="0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8"
PERPS_CONTRACT="0x05F062C924EcD9f5d4C74c567A28cc5502332fcf21828687EC20581a03F7E1C8"
OWNING_POSITION="0x7"
RECIPIENT="0x019eC96d4aEA6FdC6f0b5F393Fec3F186AeFa8F0B8356f43D07b921FF48Aa5dA"
HASH=0x0167d5b80e962d8055e2d3dcec613468115949a9cfa6de348f0b259a4d5481e6
ADDRESS=$(sncast --account $account  deploy -u $url --class-hash=$HASH  --constructor-calldata 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da 0 $NAME $SYMBOL $COLLATERAL_CONTRACT_ADDRESS $PERPS_CONTRACT $OWNING_POSITION 0x04471D52BA219221ba25A254f771bDA2BC89998895D3640A307D3C49aE262990 $RECIPIENT | grep -oE '0x[0-9a-f]{64}'| sed -n '1p')
echo Deployed upgradable vault at $ADDRESS


# sncast --account testnet deploy --class-hash 0x167d5b80e962d8055e2d3dcec613468115949a9cfa6de348f0b259a4d5481e6 --arguments '<governance_admin: ContractAddress>, <upgrade_delay: u64>, <name: ByteArray>, <symbol: ByteArray>, <pnl_collateral_contract: ContractAddress>, <perps_contract: ContractAddress>, <owning_position_id: u32>, <old_vault_address: ContractAddress>, <recipient: ContractAddress>'