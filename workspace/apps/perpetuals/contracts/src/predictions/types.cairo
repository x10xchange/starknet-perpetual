/// Price scale with 6 decimal places. A complete set of shares = PRICE_SCALE collateral units.
/// Prices range from 0 to PRICE_SCALE (0.000000 to 1.000000).
pub const PRICE_SCALE: u64 = 1_000_000;

use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use starknet::storage::{Map, Vec};
use starkware_utils::signature::stark::{HashType, Signature};
use starkware_utils::time::time::Timestamp;

#[starknet::storage_node]
pub struct Account {
    pub owning_key: felt252,
    pub collateral: u64,
    pub positions: Map<felt252, Map<felt252, u64>>,
}

#[starknet::storage_node]
pub struct Market {
    pub oracle: felt252,
    pub outcomes: Vec<felt252>,
    pub valid_outcomes: Map<felt252, bool>,
    pub winner: felt252,
    pub is_finalized: bool,
    pub pot: u256,
}

#[derive(Copy, Drop, Serde)]
pub struct SignedPredictionOutcome {
    pub signature: Signature,
    pub timestamp: u32,
    pub market_id: felt252,
    pub outcome: felt252,
}

#[derive(Copy, Drop, Hash, Serde)]
pub struct PredictionOrder {
    pub client_id: felt252,
    pub market_id: felt252,
    pub outcome: felt252,
    // Positive = buy (yes/long), negative = sell (no/short).
    // Selling means minting all other outcome shares.
    pub amount: i64,
    // Limit price per share.
    // For buyers: maximum price willing to pay.
    // For sellers: minimum price willing to accept.
    pub price: u64,
    // Maximum fee the user is willing to pay.
    pub fee_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"PredictionOrder\"(
///    \"client_id\":\"felt\",
///    \"market_id\":\"felt\",
///    \"outcome\":\"felt\",
///    \"amount\":\"i64\",
///    \"price\":\"u64\",
///    \"fee_amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const PREDICTION_ORDER_TYPE_HASH: HashType =
    selector!(
        "\"PredictionOrder\"(\"client_id\":\"felt\",\"market_id\":\"felt\",\"outcome\":\"felt\",\"amount\":\"i64\",\"price\":\"u64\",\"fee_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
    );

impl PredictionOrderStructHashImpl of StructHash<PredictionOrder> {
    fn hash_struct(self: @PredictionOrder) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(PREDICTION_ORDER_TYPE_HASH).update_with(*self).finalize()
    }
}

#[derive(Copy, Drop, Serde)]
pub struct PredictionSettlement {
    pub signature_a: Signature,
    pub signature_b: Signature,
    pub order_a: PredictionOrder,
    pub order_b: PredictionOrder,
    // Actual number of shares exchanged.
    pub actual_amount: u64,
    // Actual price per share settled at.
    pub actual_price: u64,
    // Actual fees charged to each party.
    pub actual_fee_a: u64,
    pub actual_fee_b: u64,
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
