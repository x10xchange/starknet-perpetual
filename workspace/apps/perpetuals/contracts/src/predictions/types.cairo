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
pub struct PredictionOutcome {
    pub market_id: felt252,
    pub outcome: felt252,
    pub timestamp: u32,
}

/// selector!(
///   "\"PredictionOutcome\"(
///    \"market_id\":\"felt\",
///    \"outcome\":\"felt\",
///    \"timestamp\":\"u32\"
///    )
/// ");
const PREDICTION_OUTCOME_TYPE_HASH: HashType = selector!(
    "\"PredictionOutcome\"(\"market_id\":\"felt\",\"outcome\":\"felt\",\"timestamp\":\"u32\")",
);

impl PredictionOutcomeStructHashImpl of StructHash<PredictionOutcome> {
    fn hash_struct(self: @PredictionOutcome) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(PREDICTION_OUTCOME_TYPE_HASH).update_with(*self).finalize()
    }
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
const PREDICTION_ORDER_TYPE_HASH: HashType = selector!(
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
const DEPOSIT_ARGS_TYPE_HASH: HashType = selector!(
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
const WITHDRAW_ARGS_TYPE_HASH: HashType = selector!(
    "\"PredictionWithdrawArgs\"(\"client_id\":\"felt\",\"to_position_id\":\"felt\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
);

impl PredictionWithdrawArgsStructHashImpl of StructHash<PredictionWithdrawArgs> {
    fn hash_struct(self: @PredictionWithdrawArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(WITHDRAW_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use starkware_utils::math::utils::to_base_16_string;
    use super::*;

    #[test]
    fn test_prediction_outcome_type_hash() {
        let expected = selector!(
            "\"PredictionOutcome\"(\"market_id\":\"felt\",\"outcome\":\"felt\",\"timestamp\":\"u32\")",
        );
        assert_eq!(
            to_base_16_string(PREDICTION_OUTCOME_TYPE_HASH), to_base_16_string(expected),
        );
    }

    #[test]
    fn test_prediction_outcome_hash_struct() {
        let outcome = PredictionOutcome { market_id: 1, outcome: 2, timestamp: 3 };
        assert_eq!(
            to_base_16_string(outcome.hash_struct()),
            "0x01afbe8d898657bc923f70d3667751fccf1a53d5ca8b38cbb3a1a0064c46de1d",
        );
    }

    #[test]
    fn test_prediction_order_type_hash() {
        let expected = selector!(
            "\"PredictionOrder\"(\"client_id\":\"felt\",\"market_id\":\"felt\",\"outcome\":\"felt\",\"amount\":\"i64\",\"price\":\"u64\",\"fee_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(PREDICTION_ORDER_TYPE_HASH), to_base_16_string(expected),
        );
    }

    #[test]
    fn test_prediction_order_hash_struct() {
        let order = PredictionOrder {
            client_id: 1,
            market_id: 2,
            outcome: 3,
            amount: 4,
            price: 5,
            fee_amount: 6,
            expiration: Timestamp { seconds: 7 },
            salt: 8,
        };
        assert_eq!(
            to_base_16_string(order.hash_struct()),
            "0x04a069da0a42c4a23fe75e7de4f5378b9a68eadf8def62f9fa222ec3fae4e49d",
        );
    }

    #[test]
    fn test_prediction_deposit_type_hash() {
        let expected = selector!(
            "\"PredictionDepositArgs\"(\"client_id\":\"felt\",\"from_position_id\":\"felt\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(DEPOSIT_ARGS_TYPE_HASH), to_base_16_string(expected),
        );
    }

    #[test]
    fn test_prediction_deposit_hash_struct() {
        let deposit = PredictionDepositArgs {
            client_id: 1,
            from_position_id: PositionId { value: 2 },
            amount: 3,
            expiration: Timestamp { seconds: 4 },
            salt: 5,
        };
        assert_eq!(
            to_base_16_string(deposit.hash_struct()),
            "0x03c6812feeea88cc83c0022acfdf340e5424e907b47484dce3ce8a63979efcb4",
        );
    }

    #[test]
    fn test_prediction_withdraw_type_hash() {
        let expected = selector!(
            "\"PredictionWithdrawArgs\"(\"client_id\":\"felt\",\"to_position_id\":\"felt\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            to_base_16_string(WITHDRAW_ARGS_TYPE_HASH), to_base_16_string(expected),
        );
    }

    #[test]
    fn test_prediction_withdraw_hash_struct() {
        let withdraw = PredictionWithdrawArgs {
            client_id: 1,
            to_position_id: PositionId { value: 2 },
            amount: 3,
            expiration: Timestamp { seconds: 4 },
            salt: 5,
        };
        assert_eq!(
            to_base_16_string(withdraw.hash_struct()),
            "0x0062462ea5d74e057283dba9cdcc7d02c431037f8b4b04d2e6791c3b2642b9a1",
        );
    }
}
