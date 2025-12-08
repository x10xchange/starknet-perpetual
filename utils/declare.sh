#!/bin/bash

helpFunction()
{
   echo ""
   echo "Usage: $0 -a Account name -u RpcUrl -c contract -p package"
   exit 1 # Exit script after printing help
}

while getopts "a:u:c:p:" opt
do
   case "$opt" in
      a ) account="$OPTARG" ;;
      u ) url="$OPTARG" ;;
      c ) contract="$OPTARG" ;;
      p ) package="$OPTARG" ;;
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
if [ -z "$contract" ]
then
   echo "Contract is missing pass -c";
   helpFunction
fi
if [ -z "$package" ]
then
   echo "Package is missing pass -p";
   helpFunction
fi

CLASS_HASH=$(sncast --account $account utils class-hash  -c $contract --package $package | grep -oE '0x[0-9a-f]{64}'| sed -n '1p')
sncast --account $account declare -u $url -c $contract --package $package
echo $CLASS_HASH