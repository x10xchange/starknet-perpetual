use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use starknet::storage::Map;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct MarketPosition {
    pub amount: u64,
}

#[starknet::storage_node]
pub struct Account {
    pub owning_key: felt252,
    pub collateral: u64,
    pub tokens: Map<felt252, Map<felt252, MarketPosition>>,
}

#[derive(Copy, Drop, Hash, Serde)]
pub struct PredictionDepositArgs {
    pub client_id: felt252,
    pub from_position_id: PositionId,
    pub amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"PredictionDepositArgs\"(
///    \"client_id\":\"felt\",
///    \"from_position_id\":\"felt\",
///    \"amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const DEPOSIT_ARGS_TYPE_HASH: HashType =
    selector!(
        "\"PredictionDepositArgs\"(\"client_id\":\"felt\",\"from_position_id\":\"felt\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
    );

impl PredictionDepositArgsStructHashImpl of StructHash<PredictionDepositArgs> {
    fn hash_struct(self: @PredictionDepositArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(DEPOSIT_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Copy, Drop, Hash, Serde)]
pub struct PredictionWithdrawArgs {
    pub client_id: felt252,
    pub to_position_id: PositionId,
    pub amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"PredictionWithdrawArgs\"(
///    \"client_id\":\"felt\",
///    \"to_position_id\":\"felt\",
///    \"amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const WITHDRAW_ARGS_TYPE_HASH: HashType =
    selector!(
        "\"PredictionWithdrawArgs\"(\"client_id\":\"felt\",\"to_position_id\":\"felt\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
    );

impl PredictionWithdrawArgsStructHashImpl of StructHash<PredictionWithdrawArgs> {
    fn hash_struct(self: @PredictionWithdrawArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(WITHDRAW_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}
