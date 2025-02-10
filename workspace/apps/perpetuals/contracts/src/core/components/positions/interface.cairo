use contracts_commons::types::time::time::Timestamp;
use contracts_commons::types::{PublicKey, Signature};
use perpetuals::core::types::PositionId;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IPositions<TContractState> {
    // Position Flows
    fn new_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        owner_public_key: PublicKey,
        owner_account: ContractAddress,
    );
    fn set_owner_account(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        position_id: PositionId,
        public_key: PublicKey,
        new_account_owner: ContractAddress,
        expiration: Timestamp,
    );
    fn set_public_key_request(
        ref self: TContractState,
        signature: Signature,
        position_id: PositionId,
        new_public_key: PublicKey,
        expiration: Timestamp,
    );
    fn set_public_key(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        new_public_key: PublicKey,
        expiration: Timestamp,
    );
}
