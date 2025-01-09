use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
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

const ORDER_TYPE_HASH: felt252 = 0x2bac1bd11aeb68b0d97408f089a43e23b5704a15b881de50d5c5776ecfc5fe0;

impl StructHashImpl of StructHash<Order> {
    fn hash_struct(self: @Order) -> felt252 {
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
