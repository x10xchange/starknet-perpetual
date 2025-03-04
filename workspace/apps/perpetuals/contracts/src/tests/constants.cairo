use contracts_commons::constants::{DAY, MAX_U128, MINUTE, WEEK};
use contracts_commons::types::fixed_two_decimal::{FixedTwoDecimal, FixedTwoDecimalTrait};
use contracts_commons::types::time::time::{Time, TimeDelta};
use core::num::traits::{One, Zero};
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::collateral::{CollateralTimelyData, CollateralTrait};
use perpetuals::core::types::asset::synthetic::{
    SyntheticConfig, SyntheticTimelyData, SyntheticTrait,
};

use perpetuals::core::types::asset::{AssetId, AssetIdTrait, AssetStatus};
use perpetuals::core::types::price::{PRICE_SCALE, Price, PriceTrait};
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use starknet::{ContractAddress, contract_address_const};


pub fn OPERATOR_PUBLIC_KEY() -> felt252 {
    StarkCurveKeyPairImpl::from_secret_key('OPERATOR_PRIVATE_KEY').public_key
}
pub fn KEY_PAIR_1() -> StarkKeyPair {
    StarkCurveKeyPairImpl::from_secret_key('PRIVATE_KEY_1')
}
pub fn KEY_PAIR_2() -> StarkKeyPair {
    StarkCurveKeyPairImpl::from_secret_key('PRIVATE_KEY_2')
}
pub fn KEY_PAIR_3() -> StarkKeyPair {
    StarkCurveKeyPairImpl::from_secret_key('PRIVATE_KEY_3')
}
pub fn COLLATERAL_OWNER() -> ContractAddress nopanic {
    contract_address_const::<'COLLATERAL_OWNER'>()
}
pub fn POSITION_OWNER_1() -> ContractAddress nopanic {
    contract_address_const::<'POSITION_OWNER_1'>()
}
pub fn POSITION_OWNER_2() -> ContractAddress nopanic {
    contract_address_const::<'POSITION_OWNER_2'>()
}
pub fn TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'TOKEN_ADDRESS'>()
}
pub fn GOVERNANCE_ADMIN() -> ContractAddress {
    contract_address_const::<'GOVERNANCE_ADMIN'>()
}
pub fn APP_ROLE_ADMIN() -> ContractAddress {
    contract_address_const::<'APP_ROLE_ADMIN'>()
}
pub fn APP_GOVERNOR() -> ContractAddress {
    contract_address_const::<'APP_GOVERNOR'>()
}
pub fn OPERATOR() -> ContractAddress {
    contract_address_const::<'OPERATOR'>()
}

pub fn COLLATERAL_TIMELY_DATA() -> CollateralTimelyData {
    CollateralTrait::timely_data(price: One::one(), last_price_update: Time::now())
}

pub fn SYNTHETIC_CONFIG() -> SyntheticConfig {
    SyntheticTrait::config(
        status: AssetStatus::ACTIVE,
        risk_factor_first_tier_boundary: MAX_U128,
        risk_factor_tier_size: Zero::zero(),
        quorum: SYNTHETIC_QUORUM,
        resolution: SYNTHETIC_RESOLUTION,
    )
}

pub fn SYNTHETIC_PENDING_CONFIG() -> SyntheticConfig {
    SyntheticTrait::config(
        status: AssetStatus::PENDING,
        risk_factor_first_tier_boundary: MAX_U128,
        risk_factor_tier_size: Zero::zero(),
        quorum: SYNTHETIC_QUORUM,
        resolution: SYNTHETIC_RESOLUTION,
    )
}

pub fn SYNTHETIC_TIMELY_DATA() -> SyntheticTimelyData {
    SyntheticTrait::timely_data(
        price: SYNTHETIC_PRICE(),
        // Pass non default timestamp.
        last_price_update: Time::now().add(delta: Time::seconds(count: 1)),
        funding_index: Zero::zero(),
    )
}


pub const UPGRADE_DELAY: u64 = 5_u64;
/// 1 day in seconds.
pub const MAX_PRICE_INTERVAL: TimeDelta = TimeDelta { seconds: DAY };
/// 1 day in seconds.
pub const MAX_FUNDING_INTERVAL: TimeDelta = TimeDelta { seconds: DAY };
/// 10 minutes in seconds.
pub const MAX_ORACLE_PRICE_VALIDITY: TimeDelta = TimeDelta { seconds: 10 * MINUTE };
pub const DEPOSIT_GRACE_PERIOD: TimeDelta = TimeDelta { seconds: WEEK };
pub const MAX_FUNDING_RATE: u32 = 35792; // Which is ~3% in an hour.
pub const COLLATERAL_QUORUM: u8 = 0;
pub const COLLATERAL_QUANTUM: u64 = 1_000;
pub const SYNTHETIC_QUORUM: u8 = 1;
pub const SYNTHETIC_RESOLUTION: u64 = 1_000_000_000;
pub const INITIAL_SUPPLY: u256 = 10_000_000_000_000_000;
pub const WITHDRAW_AMOUNT: u64 = 1000;
pub const DEPOSIT_AMOUNT: u64 = 10;
pub const TRANSFER_AMOUNT: u64 = 1000;
pub const COLLATERAL_BALANCE_AMOUNT: i64 = 2000;
pub const SYNTHETIC_BALANCE_AMOUNT: i64 = 20;
pub const CONTRACT_INIT_BALANCE: u128 = 1_000_000_000;
pub const USER_INIT_BALANCE: u128 = 100_000_000;

pub const POSITION_ID_1: PositionId = PositionId { value: 2 };
pub const POSITION_ID_2: PositionId = PositionId { value: 3 };

pub const ORACLE_A_NAME: felt252 = 'ORCLA';
pub const ORACLE_B_NAME: felt252 = 'ORCLB';

/// Assets IDs
pub fn COLLATERAL_ASSET_ID() -> AssetId {
    AssetIdTrait::new(value: selector!("COLLATERAL_ASSET_ID"))
}
pub fn SYNTHETIC_ASSET_ID_1() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_1"))
}
pub fn SYNTHETIC_ASSET_ID_2() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_2"))
}
pub fn SYNTHETIC_ASSET_ID_3() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_3"))
}

/// Risk factors
pub fn RISK_FACTOR() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}

/// Prices
pub fn SYNTHETIC_PRICE() -> Price {
    PriceTrait::new(100 * PRICE_SCALE)
}

/// Assets' metadata
pub fn COLLATERAL_NAME() -> ByteArray {
    "COLLATERAL_NAME"
}
pub fn COLLATERAL_SYMBOL() -> ByteArray {
    "COL"
}
pub fn SYNTHETIC_SYMBOL() -> ByteArray {
    "SYN"
}
