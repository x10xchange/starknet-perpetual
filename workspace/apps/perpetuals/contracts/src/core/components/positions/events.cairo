use contracts_commons::types::PublicKey;
use contracts_commons::types::time::time::Timestamp;
use perpetuals::core::types::PositionId;
use starknet::ContractAddress;


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct NewPosition {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub owner_public_key: PublicKey,
    #[key]
    pub owner_account: ContractAddress,
}


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct SetOwnerAccount {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub public_key: PublicKey,
    #[key]
    pub new_owner_account: ContractAddress,
    pub set_owner_account_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct SetPublicKeyRequest {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub new_public_key: PublicKey,
    pub old_public_key: PublicKey,
    pub expiration: Timestamp,
    #[key]
    pub set_public_key_request_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct SetPublicKey {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub new_public_key: PublicKey,
    pub old_public_key: PublicKey,
    pub expiration: Timestamp,
    #[key]
    pub set_public_key_request_hash: felt252,
}
