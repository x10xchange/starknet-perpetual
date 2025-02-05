use contracts_commons::types::HashType;
use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct WithdrawArgs {
    pub position_id: PositionId,
    pub salt: felt252,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub recipient: ContractAddress,
    pub expiration: Timestamp,
}

/// selector!(
///   "\"WithdrawArgs\"(
///    \"position_id\":\"PositionId\",
///    \"salt\":\"felt\",
///    \"recipient\":\"ContractAddress\"
///    \"collateral_id\":\"AssetId\",
///    \"amount\":\"u64\",
///    \"expiration\":\"Timestamp\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
/// );
const WITHDRAW_ARGS_TYPE_HASH: HashType =
    0x37c3df1ba2eb3467001cbd2a4f75769284b49103ec57f4cbf6ce7a99b3e9c0c;

impl StructHashImpl of StructHash<WithdrawArgs> {
    fn hash_struct(self: @WithdrawArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(WITHDRAW_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::WITHDRAW_ARGS_TYPE_HASH;

    #[test]
    fn test_withdraw_type_hash() {
        let expected = selector!(
            "\"WithdrawArgs\"(\"position_id\":\"PositionId\",\"salt\":\"felt\",\"recipient\":\"ContractAddress\",\"collateral_id\":\"AssetId\",\"amount\":\"u64\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(WITHDRAW_ARGS_TYPE_HASH, expected);
    }
}
