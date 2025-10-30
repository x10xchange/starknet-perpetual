use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;


#[derive(Copy, Drop, Hash, Serde)]
/// An order to convert a position into a vault.
pub struct ConvertPositionToVault {
    pub position_to_convert: PositionId,
    pub vault_asset_id: AssetId,
    pub expiration: Timestamp,
}

pub const CONVERT_POSITION_TO_VAULT_TYPE_HASH: HashType = selector!(
    "\"ConvertPositionToVault\"(\"position_to_convert\":\"PositionId\",\"vault_asset_id\":\"AssetId\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
);

impl StructHashImpl of StructHash<ConvertPositionToVault> {
    fn hash_struct(self: @ConvertPositionToVault) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(CONVERT_POSITION_TO_VAULT_TYPE_HASH).update_with(*self).finalize()
    }
}

#[cfg(test)]
mod tests {
    use openzeppelin_testing::common::IntoBase16String;
    use super::CONVERT_POSITION_TO_VAULT_TYPE_HASH;


    #[test]
    fn test_convert_position_to_vault_type_hash() {
        let expected = selector!(
            "\"ConvertPositionToVault\"(\"position_to_convert\":\"PositionId\",\"vault_asset_id\":\"AssetId\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"AssetId\"(\"value\":\"felt\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        assert_eq!(
            CONVERT_POSITION_TO_VAULT_TYPE_HASH.into_base_16_string(),
            expected.into_base_16_string(),
        );
    }
}

