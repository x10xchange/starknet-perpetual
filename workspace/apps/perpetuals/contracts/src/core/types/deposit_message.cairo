use contracts_commons::types::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::{AssetAmount, PositionId};
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct DepositMessage {
    pub position_id: PositionId,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
    pub owner_public_key: felt252,
    pub owner_account: ContractAddress,
    pub depositing_address: ContractAddress,
}


/// selector!(
///   "\"DepositMessage\"(
///    \"position_id\":\"PositionId\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral\":\"AssetAmount\",
///    \"owner_public_key\":\"felt\"
///    \"owner_account\":\"ContractAddress\"
///    \"depositing_address\":\"ContractAddress\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
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
    0x29dd3d9e176ff518cc692796e483898a2e82606dcf20e1db468e69f9b457987;

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
            "\"DepositMessage\"(\"position_id\":\"PositionId\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"owner_public_key\":\"felt\",\"owner_account\":\"ContractAddress\",\"depositing_address\":\"ContractAddress\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(DEPOSIT_MESSAGE_TYPE_HASH, expected);
    }
}

