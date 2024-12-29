use contracts_commons::types::time::time::Timestamp;
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
}


/// selector!(
///   "\"DepositMessage\"(
///    \"position_id\":\"PositionId\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral\":\"AssetAmount\",
///    \"owner_public_key\":\"felt\"
///    \"owner_account\":\"ContractAddress\"
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
    0xbd3cd29a87ff6b03a779fe5dc74e3ad33963aa9d4bddd6e6cb21071cb222c4;

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
            "\"DepositMessage\"(\"position_id\":\"PositionId\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"owner_public_key\":\"felt\",\"owner_account\":\"ContractAddress\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(DEPOSIT_MESSAGE_TYPE_HASH, expected);
    }
}

