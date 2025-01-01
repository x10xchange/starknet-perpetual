use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::{AssetAmount, PositionId};
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct TransferMessage {
    pub sender: PositionId,
    pub recipient: PositionId,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
    pub recipient_public_key: felt252,
    pub recipient_account: ContractAddress,
}


/// selector!(
///   "\"TransferMessage\"(
///    \"sender\":\"PositionId\",
///    \"recipient\":\"PositionId\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral\":\"AssetAmount\",
///    \"recipient_public_key\":\"felt\"
///    \"recipient_account\":\"ContractAddress\"
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
const TRANSFER_MESSAGE_TYPE_HASH: felt252 =
    0x3411899f21f2c2d87be2c481b911d8fb033af08352e5ca598f9d8d7144b8821;

impl StructHashImpl of StructHash<TransferMessage> {
    fn hash_struct(self: @TransferMessage) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(TRANSFER_MESSAGE_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::TRANSFER_MESSAGE_TYPE_HASH;

    #[test]
    fn test_transfer_type_hash() {
        let expected = selector!(
            "\"TransferMessage\"(\"sender\":\"PositionId\",\"recipient\":\"PositionId\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"recipient_public_key\":\"felt\",\"recipient_account\":\"ContractAddress\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(TRANSFER_MESSAGE_TYPE_HASH, expected);
    }
}

