use contracts_commons::constants::MAX_U128;
use core::num::traits::Zero;
use perpetuals::core::types::asset::{AssetId, AssetIdTrait};

pub const ORACLE_A_NAME: felt252 = 'ORCLA';
pub const ORACLE_B_NAME: felt252 = 'ORCLB';

#[derive(Drop)]
pub struct SyntheticConfig {
    pub asset_id: AssetId,
    pub asset_name: felt252,
    pub oracle_a_name: felt252,
    pub oracle_b_name: felt252,
    pub risk_factor_tiers: Span<u8>,
    pub risk_factor_first_tier_boundary: u128,
    pub risk_factor_tier_size: u128,
    pub quorum: u8,
    pub resolution: u64,
}

pub fn SYNTHETIC_CONFIG_1() -> SyntheticConfig {
    SyntheticConfig {
        asset_id: AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_1")),
        asset_name: 'SYN_1',
        oracle_a_name: 'ORACLE_A_SYN_1',
        oracle_b_name: 'ORACLE_B_SYN_1',
        risk_factor_tiers: array![50].span(),
        risk_factor_first_tier_boundary: MAX_U128,
        risk_factor_tier_size: Zero::zero(),
        quorum: 1,
        resolution: 1_000_000_000,
    }
}

pub fn SYNTHETIC_CONFIG_2() -> SyntheticConfig {
    SyntheticConfig {
        asset_id: AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_2")),
        asset_name: 'SYN_2',
        oracle_a_name: 'ORACLE_A_SYN_2',
        oracle_b_name: 'ORACLE_B_SYN_2',
        risk_factor_tiers: array![25].span(),
        risk_factor_first_tier_boundary: MAX_U128,
        risk_factor_tier_size: Zero::zero(),
        quorum: 1,
        resolution: 1_000_000_000,
    }
}

pub fn SYNTHETIC_CONFIG_3() -> SyntheticConfig {
    SyntheticConfig {
        asset_id: AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_3")),
        asset_name: 'SYN_3',
        oracle_a_name: 'ORACLE_A_SYN_3',
        oracle_b_name: 'ORACLE_B_SYN_3',
        risk_factor_tiers: array![10].span(),
        risk_factor_first_tier_boundary: MAX_U128,
        risk_factor_tier_size: Zero::zero(),
        quorum: 1,
        resolution: 1_000_000_000,
    }
}
