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


/// selector!(
///   "\"InvestInVault\"(
///    \"from_position_id\":\"PositionId\",
///    \"vault_id\":\"PositionId\",
///    \"amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const INVEST_IN_VAULT_TYPE_HASH: HashType =
    0x02a65ee4e1411742e955f29a41e4044248c9cc87058cc9c45c18fb0361caf810;

/// selector!(
///   "\"RedeemFromVault\"(
///    \"vault_id\":\"PositionId\",
///    \"to_position_id\":\"PositionId\",
///    \"amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const REDEEM_FROM_VAULT_TYPE_HASH: HashType =
    0x037fe967135296cbf99efc8ebf99277f9cdc036093d4fe6ff661588245d80a28;

/// selector!(
///   "\"ConvertPositionToVault\"(
///    \"position_to_convert\":\"PositionId\",
///    \"position_receiving_shares\":\"PositionId\",
///    \"initial_shares\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    )
///    \"PositionId\"(
///    \"value\":\"u32\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );

#[cfg(test)]
mod tests {
    // use openzeppelin_testing::common::IntoBase16String;
    // use super::{
    //     CONVERT_POSITION_TO_VAULT_TYPE_HASH, INVEST_IN_VAULT_TYPE_HASH,
    //     REDEEM_FROM_VAULT_TYPE_HASH,
    // };

    // #[test]
    // fn test_invest_in_vault_type_hash() {
    //     let expected = selector!(
    //         "\"InvestInVault\"(\"from_position_id\":\"PositionId\",\"vault_id\":\"PositionId\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
    //     );
    //     assert_eq!(INVEST_IN_VAULT_TYPE_HASH.into_base_16_string(),
    //     expected.into_base_16_string());
    // }

    // #[test]
    // fn test_redeem_from_vault_type_hash() {
    //     let expected = selector!(
    //         "\"RedeemFromVault\"(\"vault_id\":\"PositionId\",\"to_position_id\":\"PositionId\",\"amount\":\"u64\",\"expiration\":\"Timestamp\",\"salt\":\"felt\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
    //     );
    //     assert_eq!(
    //         REDEEM_FROM_VAULT_TYPE_HASH.into_base_16_string(), expected.into_base_16_string(),
    //     );
    // }

    // #[test]
    // fn test_convert_position_to_vault_type_hash() {
    //     let expected = selector!(
    //         "\"ConvertPositionToVault\"(\"position_to_convert\":\"PositionId\",\"position_receiving_shares\":\"PositionId\",\"initial_shares\":\"u64\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
    //     );
    //     assert_eq!(
    //         CONVERT_POSITION_TO_VAULT_TYPE_HASH.into_base_16_string(),
    //         expected.into_base_16_string(),
    //     );
    // }
}

