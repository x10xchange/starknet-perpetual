use contracts_commons::types::time::time::Timestamp;
use contracts_commons::types::{HashType, PublicKey};
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::PositionId;

#[derive(Copy, Drop, Hash, Serde)]
pub struct SetPublicKeyArgs {
    pub position_id: PositionId,
    pub new_public_key: PublicKey,
    pub expiration: Timestamp,
}


/// selector!(
///   "\"SetPublicKeyArgs\"(
///    \"position_id\":\"PositionId\",
///    \"new_public_key\":\"felt\",
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
    0x38c4dbc4041b98ccb5dfac20bca95760aa1b2a94099b0f4fa220f7134649711;

impl StructHashImpl of StructHash<SetPublicKeyArgs> {
    fn hash_struct(self: @SetPublicKeyArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(SET_PUBLIC_KEY_ARGS_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::SET_PUBLIC_KEY_ARGS_HASH;

    #[test]
    fn test_update_position_public_key_type_hash() {
        let expected = selector!(
            "\"SetPublicKeyArgs\"(\"position_id\":\"PositionId\",\"new_public_key\":\"felt\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(SET_PUBLIC_KEY_ARGS_HASH, expected);
    }
}
