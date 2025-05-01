# HASH=$(starkli declare -w target/dev/perpetuals_Core.contract_class.json  --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5)
# ADDRESS=$(starkli deploy -w "$HASH"  0x19ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da  0x0  0x31857064564ed0ff978e687456963cba09c2c6985d8f9300a1de4962fafa054  0x5ba91db44b3e6a4485b5dbfcb17d791faa9cb6890a42731b66b3536b28b8ed5  0x1  0x93a80  0x3f480  0x93a80  0x8bd0  0x15180  0x19ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da  0x19ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5)
# echo $ADDRESS


# starkli invoke -w "$ADDRESS" register_app_role_admin 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" register_operator 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" register_governance_admin 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" register_upgrade_governor 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" register_security_admin 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" register_security_agent 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
# starkli invoke -w "$ADDRESS" register_app_governor 0x019ec96d4aea6fdc6f0b5f393fec3f186aefa8f0b8356f43d07b921ff48aa5da --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5

# echo "Contract deployed and initialised at address: ${ADDRESS}"



HASH=$(starkli declare -w target/dev/perpetuals_Core.contract_class.json  --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5)
ADDRESS=0x027c6791a79cf9b0176d83dab10c57a0c86a31a13e58bd11649d631ca83f440d
starkli invoke -w "$ADDRESS" add_new_implementation "${HASH}" 1 0 --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5
starkli invoke -w "$ADDRESS" replace_to "${HASH}" 1 0 --account onchain_deploy/testnet_keys/account.json --private-key 0x06c73b5813f1cdb4051eedfcf49f28285d062bf59d9f03a88cab147a1a856ce5

