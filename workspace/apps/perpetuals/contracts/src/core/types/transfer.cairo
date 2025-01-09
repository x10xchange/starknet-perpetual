use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::{AssetAmount, PositionId};
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash, Serde)]
pub struct TransferArgs {
    pub sender: PositionId,
    pub recipient: PositionId,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
    pub recipient_public_key: felt252,
    pub recipient_account: ContractAddress,
}


/// selector!(
///   "\"TransferArgs\"(
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
const TRANSFER_ARGS_TYPE_HASH: felt252 =
    0x295744ddc78fc1d31c140d9a418978d269dac230225a9279fc154de3ab2e0f3;

impl StructHashImpl of StructHash<TransferArgs> {
    fn hash_struct(self: @TransferArgs) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(TRANSFER_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::TRANSFER_ARGS_TYPE_HASH;

    #[test]
    fn test_transfer_type_hash() {
        let expected = selector!(
            "\"TransferArgs\"(\"sender\":\"PositionId\",\"recipient\":\"PositionId\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\",\"recipient_public_key\":\"felt\",\"recipient_account\":\"ContractAddress\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(TRANSFER_ARGS_TYPE_HASH, expected);
    }
}

