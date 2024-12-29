use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::{AssetAmount, PositionId};
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct WithdrawMessage {
    pub position_id: PositionId,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
    pub recipient: ContractAddress,
}


/// selector!(
///   "\"WithdrawMessage\"(
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
const WITHDRAW_MESSAGE_TYPE_HASH: felt252 =
    0x57d2c2a95b7df8469c5d9212753fd4bb55a6f93444175e254f1f9cef3e32b3;

impl StructHashImpl of StructHash<WithdrawMessage> {
    fn hash_struct(self: @WithdrawMessage) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(WITHDRAW_MESSAGE_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::WITHDRAW_MESSAGE_TYPE_HASH;

    #[test]
    fn test_withdraw_type_hash() {
        let expected = selector!(
            "\"WithdrawMessage\"(\"position_id\":\"PositionId\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"recipient\":\"ContractAddress\")\"PositionId\"(\"value\":\"felt\")\"AssetAmount\"(\"asset_id\":\"felt\",\"amount\":\"i128\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(WITHDRAW_MESSAGE_TYPE_HASH, expected);
    }
}
