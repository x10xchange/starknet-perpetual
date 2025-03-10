use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::errors::{illegal_base_to_quote_ratio_err, illegal_fee_to_quote_ratio_err};
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starkware_utils::math::abs::Abs;
use starkware_utils::types::HashType;
use starkware_utils::types::time::time::Timestamp;
use starkware_utils::utils::validate_ratio;

pub const VERSION: u8 = 0;

#[derive(Copy, Drop, Hash, Serde)]
// An order to buy or sell a synthetic asset for a collateral asset.
// The base amount and quote amount have opposite signs.
pub struct Order {
    pub position_id: PositionId,
    // The synthetic asset to be bought or sold.
    pub base_asset_id: AssetId,
    // The amount of the synthetic asset to be bought or sold.
    pub base_amount: i64,
    // The collateral asset.
    pub quote_asset_id: AssetId,
    // The amount of the collateral asset to be paid or received.
    pub quote_amount: i64,
    // The collateral asset.
    pub fee_asset_id: AssetId,
    // The amount of the collateral asset to be paid.
    pub fee_amount: u64,
    // The expiration time of the order.
    pub expiration: Timestamp,
    // A random value to make each order unique.
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
        assert!(ORDER_TYPE_HASH.into_base_16_string() == expected.into_base_16_string());
    }
}
