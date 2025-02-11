use contracts_commons::types::time::time::Timestamp;
use contracts_commons::types::{HashType, PublicKey};
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::PositionId;
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct SetOwnerAccountArgs {
    pub position_id: PositionId,
    pub public_key: PublicKey,
    pub new_account_owner: ContractAddress,
    pub expiration: Timestamp,
}


/// selector!(
///   "\"SetOwnerAccountArgs\"(
///    \"position_id\":\"PositionId\",
///    \"public_key\":\"felt\",
///    \"new_account_owner\":\"ContractAddress\",
///    \"expiration\":\"Timestamp\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const SET_OWNER_ACCOUNT_ARGS_HASH: HashType =
    0x3747d879b584b295f863344299e3e30178fbcffc3df0da44e8df7cdf67da11f;

impl StructHashImpl of StructHash<SetOwnerAccountArgs> {
    fn hash_struct(self: @SetOwnerAccountArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(SET_OWNER_ACCOUNT_ARGS_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::SET_OWNER_ACCOUNT_ARGS_HASH;

    #[test]
    fn test_set_owner_account_type_hash() {
        let expected = selector!(
            "\"SetOwnerAccountArgs\"(\"position_id\":\"PositionId\",\"public_key\":\"felt\",\"new_account_owner\":\"ContractAddress\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(SET_OWNER_ACCOUNT_ARGS_HASH, expected);
    }
}
