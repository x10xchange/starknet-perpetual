use contracts_commons::types::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::AssetAmount;
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct DepositMessage {
    pub position_id: felt252,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
    pub public_key: felt252,
    pub account_owner: ContractAddress,
    pub depositing_address: ContractAddress,
}


/// selector!(
///   "\"DepositMessage\"(
///    \"position_id\":\"felt\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral\":\"AssetAmount\",
///    \"public_key\":\"felt\"
///    \"account_owner\":\"ContractAddress\"
///    \"depositing_address\":\"ContractAddress\"
///    )
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
///    \"AssetAmount\"(
///    \"asset_id\":\"AssetId\",
///    \"amount\":\"i64\",
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
/// );
const DEPOSIT_MESSAGE_TYPE_HASH: felt252 =
    0x2af30f1256592679c5b14452ae3ee21e47cf64caf2941ebccdf0a191ca96f26;

impl StructHashImpl of StructHash<DepositMessage> {
    fn hash_struct(self: @DepositMessage) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(DEPOSIT_MESSAGE_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::DEPOSIT_MESSAGE_TYPE_HASH;

    #[test]
    fn test_deposit_type_hash() {
        let expected = selector!(
            "\"DepositMessage\"(\"position_id\":\"felt\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"public_key\":\"felt\",\"account_owner\":\"ContractAddress\",\"depositing_address\":\"ContractAddress\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(DEPOSIT_MESSAGE_TYPE_HASH, expected);
    }
}

