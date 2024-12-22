use contracts_commons::types::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::AssetAmount;

pub const VERSION: u8 = 0;

#[derive(Copy, Drop, Hash, Serde)]
pub struct Order {
    pub position_id: felt252,
    pub base: AssetAmount,
    pub quote: AssetAmount,
    pub fee: AssetAmount,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"Order\"(
///    \"position_id\":\"felt\",
///    \"base\":\"AssetAmount\",
///    \"quote\":\"AssetAmount\",
///    \"fee\":\"AssetAmount\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\",
///    )
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

const ORDER_MESSAGE_TYPE_HASH: felt252 =
    0x1cf3c762f8266a13fed51baa0e9366ed996bd522982dd397378726ba0d31f69;

impl StructHashImpl of StructHash<Order> {
    fn hash_struct(self: @Order) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(ORDER_MESSAGE_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::ORDER_MESSAGE_TYPE_HASH;

    #[test]
    fn test_order_type_hash() {
        let expected = selector!(
            "\"Order\"(\"position_id\":\"felt\",\"base\":\"AssetAmount\",\"quote\":\"AssetAmount\",\"fee\":\"AssetAmount\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i128\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(ORDER_MESSAGE_TYPE_HASH, expected);
    }
}
