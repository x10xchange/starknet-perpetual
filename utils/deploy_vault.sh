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


NAME=$(str_to_felt_array "VAULT")
SYMBOL=$(str_to_felt_array "VLT")
COLLATERAL_CONTRACT_ADDRESS="0x5ba91db44b3e6a4485b5dbfcb17d791faa9cb6890a42731b66b3536b28b8ed5"
PERPS_CONTRACT="0x05F062C924EcD9f5d4C74c567A28cc5502332fcf21828687EC20581a03F7E1C8"
OWNING_POSITION="0x7"
RECIPIENT="0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da"
INITIAL_PRICE=$(decimal_to_hex 1000000)
HASH=$(./utils/declare.sh -a $account -u $url -c ProtocolVault -p vault)
echo Hash is $HASH
ADDRESS=$(sncast --account $account  deploy -u $url --class-hash=$HASH  --constructor-calldata $NAME $SYMBOL $COLLATERAL_CONTRACT_ADDRESS $PERPS_CONTRACT $OWNING_POSITION $RECIPIENT $INITIAL_PRICE | grep -oE '0x[0-9a-f]{64}'| sed -n '1p')
