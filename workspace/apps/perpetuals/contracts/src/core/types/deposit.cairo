use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::{AssetAmount, PositionId};

#[derive(Copy, Drop, Hash, Serde)]
pub struct DepositArgs {
    pub position_id: PositionId,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral: AssetAmount,
}


/// selector!(
///   "\"DepositArgs\"(
///    \"position_id\":\"PositionId\",
///    \"salt\":\"felt\",
///    \"expiration\":\"Timestamp\",
///    \"collateral\":\"AssetAmount\",
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
const DEPOSIT_ARGS_TYPE_HASH: felt252 =
    0x3b541a25895ab4c6fd25da6d89aa4573288e06d1e8a017edb82c049f37cf833;

impl StructHashImpl of StructHash<DepositArgs> {
    fn hash_struct(self: @DepositArgs) -> felt252 {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(DEPOSIT_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use super::DEPOSIT_ARGS_TYPE_HASH;

    #[test]
    fn test_deposit_type_hash() {
        let expected = selector!(
            "\"DepositArgs\"(\"position_id\":\"PositionId\",\"salt\":\"felt\",\"expiration\":\"Timestamp\",\"collateral\":\"AssetAmount\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetAmount\"(\"asset_id\":\"AssetId\",\"amount\":\"i64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(DEPOSIT_ARGS_TYPE_HASH, expected);
    }
}

