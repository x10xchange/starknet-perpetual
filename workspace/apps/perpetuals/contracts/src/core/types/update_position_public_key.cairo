use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::PositionId;

#[derive(Copy, Drop, Hash, Serde)]
pub struct UpdatePositionPublicKeyArgs {
    pub position_id: PositionId,
    pub expiration: Timestamp,
    pub new_public_key: felt252,
}


/// selector!(
///   "\"UpdatePositionPublicKeyArgs\"(
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
const UPDATE_POSITION_PUBLIC_KEY_ARGS_HASH: felt252 =
    0x40c7d98c847517b1e4e365be17941e753a6e230a6d2616d9e734b7f377c8ce;

impl StructHashImpl of StructHash<UpdatePositionPublicKeyArgs> {
    fn hash_struct(self: @UpdatePositionPublicKeyArgs) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(UPDATE_POSITION_PUBLIC_KEY_ARGS_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::UPDATE_POSITION_PUBLIC_KEY_ARGS_HASH;

    #[test]
    fn test_update_position_public_key_type_hash() {
        let expected = selector!(
            "\"UpdatePositionPublicKeyArgs\"(\"position_id\":\"PositionId\",\"expiration\":\"Timestamp\",\"new_public_key\":\"felt252\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(UPDATE_POSITION_PUBLIC_KEY_ARGS_HASH, expected);
    }
}
