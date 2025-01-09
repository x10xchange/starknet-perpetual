use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::{AssetAmount, PositionId};
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct WithdrawArgs {
    pub position_id: PositionId,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
    pub recipient: ContractAddress,
}

/// selector!(
///   "\"WithdrawArgs\"(
///    \"position_id\":\"PositionId\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral\":\"AssetAmount\",
///    \"recipient\":\"ContractAddress\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"AssetAmount\"(
///    \"asset_id\":\"AssetId\",
///    \"amount\":\"i128\",
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
/// );
const WITHDRAW_ARGS_TYPE_HASH: felt252 =
    0x3ba0a952228788e50a6e418238b46842e5d070e7f381191adc65bade6b91c99;

impl StructHashImpl of StructHash<WithdrawArgs> {
    fn hash_struct(self: @WithdrawArgs) -> felt252 {
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
            "\"WithdrawArgs\"(\"position_id\":\"PositionId\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"recipient\":\"ContractAddress\")\"PositionId\"(\"value\":\"felt\")\"AssetAmount\"(\"asset_id\":\"felt\",\"amount\":\"i128\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(WITHDRAW_ARGS_TYPE_HASH, expected);
    }
}
