use perpetuals::core::types::asset::{AssetId, AssetIdTrait};

pub(crate) const ORACLE_A_NAME: felt252 = 'ORCLA';
pub(crate) const ORACLE_B_NAME: felt252 = 'ORCLB';

#[derive(Drop)]
pub(crate) struct SyntheticConfig {
    pub asset_id: AssetId,
    pub oracle_a_name: felt252,
    pub oracle_b_name: felt252,
    pub risk_factor: u8,
    pub quorum: u8,
    pub resolution: u64,
}

pub(crate) fn SYNTHETIC_CONFIG_1() -> SyntheticConfig {
    SyntheticConfig {
        asset_id: AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_1")),
        oracle_a_name: 'ORACLE_A_SYN_1',
        oracle_b_name: 'ORACLE_B_SYN_1',
        risk_factor: 50,
        quorum: 1,
        resolution: 1_000_000_000,
    }
}

pub(crate) fn SYNTHETIC_CONFIG_2() -> SyntheticConfig {
    SyntheticConfig {
        asset_id: AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_2")),
        oracle_a_name: 'ORACLE_A_SYN_2',
        oracle_b_name: 'ORACLE_B_SYN_2',
        risk_factor: 25,
        quorum: 1,
        resolution: 1_000_000_000,
    }
}

pub(crate) fn SYNTHETIC_CONFIG_3() -> SyntheticConfig {
    SyntheticConfig {
        asset_id: AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_3")),
        oracle_a_name: 'ORACLE_A_SYN_3',
        oracle_b_name: 'ORACLE_B_SYN_3',
        risk_factor: 10,
        quorum: 1,
        resolution: 1_000_000_000,
    }
}
