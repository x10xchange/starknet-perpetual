use contracts_commons::types::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::asset::AssetId;
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct WithdrawMessage {
    pub position_id: felt252,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral_id: AssetId,
    pub amount: u128,
    pub recipient: ContractAddress,
}


/// selector!(
///   "\"WithdrawMessage\"(
///    \"position_id\":\"felt\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral_id\":\"AssetId\",
///    \"amount\":\"u128\",
///    \"recipient\":\"ContractAddress\"
///    )
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
/// );
const WITHDRAW_MESSAGE_TYPE_HASH: felt252 =
    0x290b8032c2770acdfab97ef5e6ed7715cdeea550aabb7a1be2b93081b532d79;

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
            "\"WithdrawMessage\"(\"position_id\":\"felt\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral_id\":\"AssetId\",\"amount\":\"u128\",\"recipient\":\"ContractAddress\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(WITHDRAW_MESSAGE_TYPE_HASH, expected);
    }
}
