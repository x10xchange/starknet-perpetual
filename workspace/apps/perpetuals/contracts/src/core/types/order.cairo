use contracts_commons::math::{Abs, have_same_sign};
use contracts_commons::types::HashType;
use contracts_commons::types::time::time::Timestamp;
use contracts_commons::utils::validate_ratio;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::errors::{
    INVALID_TRADE_ACTUAL_BASE_SIGN, INVALID_TRADE_ACTUAL_QUOTE_SIGN, INVALID_ZERO_AMOUNT,
    trade_illegal_base_to_quote_ratio_err, trade_illegal_fee_to_quote_ratio_err,
};
use perpetuals::core::types::{AssetAmount, PositionId};

pub const VERSION: u8 = 0;

#[derive(Copy, Drop, Hash, Serde)]
pub struct Order {
    pub position_id: PositionId,
    pub base: AssetAmount,
    pub quote: AssetAmount,
    pub fee: AssetAmount,
    pub expiration: Timestamp,
    pub salt: felt252,
}

#[generate_trait]
pub impl OrderImpl of OrderTrait {
    fn validate_against_actual_amounts(
        self: @Order, actual_amount_base: i64, actual_amount_quote: i64, actual_fee: i64,
    ) {
        let order_amount_base = *self.base.amount;
        let order_amount_quote = *self.quote.amount;
        let order_amount_fee = *self.fee.amount;

        // Non-zero actual amount check.
        assert(actual_amount_base != 0, INVALID_ZERO_AMOUNT);
        assert(actual_amount_quote != 0, INVALID_ZERO_AMOUNT);

        // Sign Validation for amounts.
        assert(
            have_same_sign(a: order_amount_base, b: actual_amount_base),
            INVALID_TRADE_ACTUAL_BASE_SIGN,
        );
        assert(
            have_same_sign(a: order_amount_quote, b: actual_amount_quote),
            INVALID_TRADE_ACTUAL_QUOTE_SIGN,
        );

        // Validate the actual fee-to-amount ratio does not exceed the ordered fee-to-amount ratio.
        validate_ratio(
            n1: actual_fee,
            d1: actual_amount_quote.abs(),
            n2: order_amount_fee,
            d2: order_amount_quote.abs(),
            err: trade_illegal_fee_to_quote_ratio_err(*self.position_id),
        );

        // Validate the order base-to-quote ratio does not exceed the actual base-to-quote ratio.
        validate_ratio(
            n1: order_amount_base,
            d1: order_amount_quote.abs(),
            n2: actual_amount_base,
            d2: actual_amount_quote.abs(),
            err: trade_illegal_base_to_quote_ratio_err(*self.position_id),
        );
    }
}

/// selector!(
///   "\"Order\"(
///    \"position_id\":\"PositionId\",
///    \"base\":\"AssetAmount\",
///    \"quote\":\"AssetAmount\",
///    \"fee\":\"AssetAmount\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\",
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"AssetAmount\"(
///    \"asset_id\":\"AssetId\",
///    \"amount\":\"i128\",
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );

const ORDER_TYPE_HASH: HashType = 0x2bac1bd11aeb68b0d97408f089a43e23b5704a15b881de50d5c5776ecfc5fe0;

impl StructHashImpl of StructHash<Order> {
    fn hash_struct(self: @Order) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(ORDER_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::ORDER_TYPE_HASH;

    #[test]
    fn test_order_type_hash() {
        let expected = selector!(
            "\"Order\"(\"position_id\":\"felt\",\"base\":\"AssetAmount\",\"quote\":\"AssetAmount\",\"fee\":\"AssetAmount\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"felt\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i128\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(ORDER_TYPE_HASH, expected);
    }
}
