use contracts_commons::types::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::AssetAmount;
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct WithdrawMessage {
    pub position_id: felt252,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
    pub recipient: ContractAddress,
}


/// selector!(
///   "\"WithdrawMessage\"(
///    \"position_id\":\"felt\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral\":\"AssetAmount\",
///    \"recipient\":\"ContractAddress\"
///    )
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
    0x1a3b3cab9d80b1318520a0f911850fd0b2a628cf4fab9a74fcd3ecb4478c02a;

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
            "\"WithdrawMessage\"(\"position_id\":\"felt\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"recipient\":\"ContractAddress\")\"AssetAmount\"(\"asset_id\":\"felt\",\"amount\":\"i128\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(WITHDRAW_MESSAGE_TYPE_HASH, expected);
    }
}
