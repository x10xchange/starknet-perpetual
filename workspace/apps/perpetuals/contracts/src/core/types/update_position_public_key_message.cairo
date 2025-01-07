use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::PositionId;

#[derive(Copy, Drop, Hash, Serde)]
pub struct UpdatePositionPublicKeyMessage {
    pub position_id: PositionId,
    pub expiration: Timestamp,
    pub new_public_key: felt252,
}


/// selector!(
///   "\"UpdatePositionPublicKeyMessage\"(
///    \"position_id\":\"PositionId\",
///    \"expiration\":\"Timestamp\",
///    \"new_public_key\":\"felt252\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const UPDATE_POSITION_PUBLIC_KEY_MESSAGE_TYPE_HASH: felt252 =
    0x173c6d60ec931b1fead98d90a671ec24d864948665fee09f76d8470df9ae10e;

impl StructHashImpl of StructHash<UpdatePositionPublicKeyMessage> {
    fn hash_struct(self: @UpdatePositionPublicKeyMessage) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state
            .update_with(UPDATE_POSITION_PUBLIC_KEY_MESSAGE_TYPE_HASH)
            .update_with(*self)
            .finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::UPDATE_POSITION_PUBLIC_KEY_MESSAGE_TYPE_HASH;

    #[test]
    fn test_update_position_public_key_type_hash() {
        let expected = selector!(
            "\"UpdatePositionPublicKeyMessage\"(\"position_id\":\"PositionId\",\"expiration\":\"Timestamp\",\"new_public_key\":\"felt252\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(UPDATE_POSITION_PUBLIC_KEY_MESSAGE_TYPE_HASH, expected);
    }
}
