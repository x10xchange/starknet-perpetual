use contracts_commons::math::{Abs, have_same_sign};
use contracts_commons::types::HashType;
use contracts_commons::types::time::time::Timestamp;
use contracts_commons::utils::validate_ratio;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::errors::{
    INVALID_ACTUAL_BASE_SIGN, INVALID_ACTUAL_QUOTE_SIGN, INVALID_ZERO_AMOUNT,
    illegal_base_to_quote_ratio_err, illegal_fee_to_quote_ratio_err,
};
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;

pub const VERSION: u8 = 0;

#[derive(Copy, Drop, Hash, Serde)]
pub struct Order {
    pub position_id: PositionId,
    pub base_asset_id: AssetId,
    pub base_amount: i64,
    pub quote_asset_id: AssetId,
    pub quote_amount: i64,
    pub fee_asset_id: AssetId,
    pub fee_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"Order\"(
///    \"position_id\":\"PositionId\",
///    \"base_asset_id\":\"AssetId\",
///    \"base_amount\":\"i64\",
///    \"quote_asset_id\":\"AssetId\",
///    \"quote_amount\":\"i64\",
///    \"fee_asset_id\":\"AssetId\",
///    \"fee_amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );

const ORDER_TYPE_HASH: HashType = 0x36da8d51815527cabfaa9c982f564c80fa7429616739306036f1f9b608dd112;

impl StructHashImpl of StructHash<Order> {
    fn hash_struct(self: @Order) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(ORDER_TYPE_HASH).update_with(*self).finalize()
    }
}

#[generate_trait]
pub impl OrderImpl of OrderTrait {
    fn validate_against_actual_amounts(
        self: @Order, actual_amount_base: i64, actual_amount_quote: i64, actual_fee: u64,
    ) {
        // Non-zero actual amount check.
        assert(actual_amount_base != 0, INVALID_ZERO_AMOUNT);
        assert(actual_amount_quote != 0, INVALID_ZERO_AMOUNT);

        // Sign Validation for amounts.
        assert(
            have_same_sign(a: *self.base_amount, b: actual_amount_base), INVALID_ACTUAL_BASE_SIGN,
        );
        assert(
            have_same_sign(a: *self.quote_amount, b: actual_amount_quote),
            INVALID_ACTUAL_QUOTE_SIGN,
        );

        // Validate the actual fee-to-quote ratio does not exceed the ordered fee-to-quote ratio.
        validate_ratio(
            n1: actual_fee,
            d1: actual_amount_quote.abs(),
            n2: *self.fee_amount,
            d2: (*self.quote_amount).abs(),
            err: illegal_fee_to_quote_ratio_err(*self.position_id),
        );

        // Validate the order base-to-quote ratio does not exceed the actual base-to-quote ratio.
        validate_ratio(
            n1: *self.base_amount,
            d1: (*self.quote_amount).abs(),
            n2: actual_amount_base,
            d2: actual_amount_quote.abs(),
            err: illegal_base_to_quote_ratio_err(*self.position_id),
        );
    }
}

#[cfg(test)]
mod tests {
    use openzeppelin_testing::common::IntoBase16String;
    use super::ORDER_TYPE_HASH;

    #[test]
    fn test_order_type_hash() {
        let expected = selector!(
            "\"Order\"(\"position_id\":\"felt\",\"base_asset_id\":\"AssetId\",\"base_amount\":\"i64\",\"quote_asset_id\":\"AssetId\",\"quote_amount\":\"i64\",\"fee_asset_id\":\"AssetId\",\"fee_amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(ORDER_TYPE_HASH.into_base_16_string(), expected.into_base_16_string());
    }
}
