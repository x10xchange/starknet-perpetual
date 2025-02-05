use contracts_commons::types::HashType;
use contracts_commons::types::time::time::Timestamp;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;

#[derive(Copy, Drop, Hash, Serde)]
pub struct TransferArgs {
    pub position_id: PositionId,
    pub recipient: PositionId,
    pub salt: felt252,
    pub expiration: Timestamp,
    pub collateral_id: AssetId,
    pub amount: u64,
}


/// selector!(
///   "\"TransferArgs\"(
///    \"position_id\":\"PositionId\",
///    \"salt\":\"felt\",
///    \"recipient\":\"PositionId\",
///    \"collateral_id\":\"AssetId\"
///    \"amount\":\"u64\"
///    \"expiration\":\"Timestamp\",
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
/// );
const TRANSFER_ARGS_TYPE_HASH: HashType =
    0x35184c13d2cad195bb6bcec92c2fd9d47432bb88f92f2802eb40b850329fd3;

impl StructHashImpl of StructHash<TransferArgs> {
    fn hash_struct(self: @TransferArgs) -> HashType {
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
            "\"TransferArgs\"(\"position_id\":\"PositionId\",\"salt\":\"felt\",\"recipient\":\"PositionId\",\"collateral_id\":\"AssetId\",\"amount\":\"u64\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")\"AssetId\"(\"value\":\"felt\")",
        );
        assert_eq!(TRANSFER_ARGS_TYPE_HASH, expected);
    }
}

