use contracts_commons::types::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::{Fee, Signature};

pub const VERSION: u8 = 0;

#[derive(Copy, Drop, Hash, Serde)]
pub struct AssetAmount {
    pub asset_type: AssetId,
    pub amount: i128,
}

#[derive(Drop, Serde)]
pub struct Order {
    pub version: u8,
    pub signature: Signature,
    // OrderMessage
    pub position_id: felt252,
    pub base_type: AssetId,
    pub quote_type: AssetId,
    pub amount_base: i128,
    pub amount_quote: i128,
    pub fee_token_type: AssetId,
    pub fee: Fee,
    pub expiration: Timestamp,
    pub salt: felt252,
}

#[derive(Copy, Drop, Hash, Serde)]
pub struct OrderMessage {
    pub position_id: felt252,
    pub base: AssetAmount,
    pub quote: AssetAmount,
    pub fee_token_type: AssetId,
    pub fee: Fee,
    pub expiration: Timestamp,
    pub salt: felt252,
}


/// selector!(
///   "\"OrderMessage\"(
///    \"position_id\":\"felt\",
///    \"base\":\"AssetAmount\",
///    \"quote\":\"AssetAmount\",
///    \"fee_token_type\":\"AssetId\",
///    \"fee\":\"Fee\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\",
///    )
///    \"AssetAmount\"(
///    \"asset_type\":\"AssetId\",
///    \"amount\":\"i128\",
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
///    \"Fee\"(
///    \"value\":\"u64\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );

const ORDER_MESSAGE_TYPE_HASH: felt252 =
    0x8246d4986564fd4fdb99b250b539d0aff0caead7759d3e8446f623b697c072;

impl StructHashImpl of StructHash<OrderMessage> {
    fn hash_struct(self: @OrderMessage) -> felt252 {
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
            "\"OrderMessage\"(\"position_id\":\"felt\",\"base\":\"AssetAmount\",\"quote\":\"AssetAmount\",\"fee_token_type\":\"AssetId\",\"fee\":\"Fee\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"AssetAmount\"(\"asset_type\":\"AssetId\",\"amount\":\"i128\")\"AssetId\"(\"value\":\"felt\")\"Fee\"(\"value\":\"u64\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(ORDER_MESSAGE_TYPE_HASH, expected);
    }
}
