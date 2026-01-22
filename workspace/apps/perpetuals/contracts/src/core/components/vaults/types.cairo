use perpetuals::core::types::asset::AssetId;
use starkware_utils::time::time::Seconds;

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct VaultConfig {
    pub version: u8,
    pub asset_id: AssetId,
    pub position_id: u32,
    pub last_tv_check: Seconds,
    pub tv_at_check: i128,
    pub max_tv_loss: u128,
}

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde)]
pub struct VaultProtectionParams {
    pub tv_at_check: i128,
    pub max_tv_loss: u128,
}
