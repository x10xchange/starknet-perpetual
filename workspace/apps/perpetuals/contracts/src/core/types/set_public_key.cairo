use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use starkware_utils::signature::stark::{HashType, PublicKey};
use starkware_utils::time::time::Timestamp;

#[derive(Copy, Drop, Hash, Serde)]
pub struct SetPublicKeyArgs {
    pub position_id: PositionId,
    pub old_public_key: PublicKey,
    pub new_public_key: PublicKey,
    /// Bound into the signed struct deliberately. `set_public_key` is operator-called against an
    /// approval the user registered, so if the curve rode outside this hash the operator could
    /// install the key under the wrong one and leave the position unusable.
    pub new_public_key_type: u8,
    pub expiration: Timestamp,
}


/// selector!(
///   "\"SetPublicKeyArgs\"(
///    \"position_id\":\"PositionId\",
///    \"old_public_key\":\"felt\",
///    \"new_public_key\":\"felt\",
///    \"new_public_key_type\":\"u8\",
///    \"expiration\":\"Timestamp\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const SET_PUBLIC_KEY_ARGS_HASH: HashType =
    0x19c9f8bd2162673300b75d16a40a1f487d8558acf0c19bd05daec8b48b3485a;

impl StructHashImpl of StructHash<SetPublicKeyArgs> {
    fn hash_struct(self: @SetPublicKeyArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(SET_PUBLIC_KEY_ARGS_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use starkware_utils::math::utils::to_base_16_string;
    use super::SET_PUBLIC_KEY_ARGS_HASH;

    #[test]
    fn test_update_position_public_key_type_hash() {
        let expected = selector!(
            "\"SetPublicKeyArgs\"(\"position_id\":\"PositionId\",\"old_public_key\":\"felt\",\"new_public_key\":\"felt\",\"new_public_key_type\":\"u8\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert!(to_base_16_string(SET_PUBLIC_KEY_ARGS_HASH) == to_base_16_string(expected));
    }
}
