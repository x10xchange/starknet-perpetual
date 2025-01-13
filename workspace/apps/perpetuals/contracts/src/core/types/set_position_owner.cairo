use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::PositionId;
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct SetPositionOwnerArgs {
    pub position_id: PositionId,
    pub public_key: felt252,
    pub new_account_owner: ContractAddress,
    pub expiration: Timestamp,
}


/// selector!(
///   "\"SetPositionOwnerArgs\"(
///    \"position_id\":\"PositionId\",
///    \"public_key\":\"felt\",
///    \"new_account_owner\":\"ContractAddress\",
///    \"expiration\":\"Timestamp\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const SET_POSITION_OWNER_ARGS_HASH: felt252 =
    0x258b0889c9db6c6c5ca263705f480e3f240ce5955fc78d2e0e853230a120b2c;

impl StructHashImpl of StructHash<SetPositionOwnerArgs> {
    fn hash_struct(self: @SetPositionOwnerArgs) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(SET_POSITION_OWNER_ARGS_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::SET_POSITION_OWNER_ARGS_HASH;

    #[test]
    fn test_set_position_owner_type_hash() {
        let expected = selector!(
            "\"SetPositionOwnerArgs\"(\"position_id\":\"PositionId\",\"public_key\":\"felt\",\"new_account_owner\":\"ContractAddress\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(SET_POSITION_OWNER_ARGS_HASH, expected);
    }
}
