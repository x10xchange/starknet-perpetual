use contracts_commons::types::fixed_two_decimal::{FixedTwoDecimal, FixedTwoDecimalTrait};
use contracts_commons::types::time::time::{Time, TimeDelta};
use core::num::traits::Zero;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::collateral::{
    CollateralTimelyData, VERSION as COLLATERAL_VERSION,
};
use perpetuals::core::types::asset::synthetic::{
    SyntheticConfig, SyntheticTimelyData, VERSION as SYNTHETIC_VERSION,
};
use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
use perpetuals::core::types::price::{Price, PriceTrait, TWO_POW_28};
use snforge_std::signature::KeyPair;
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use starknet::{ContractAddress, contract_address_const};


pub fn OPERATOR_PUBLIC_KEY() -> felt252 {
    StarkCurveKeyPairImpl::from_secret_key('OPERATOR_PRIVATE_KEY').public_key
}
pub fn KEY_PAIR_1() -> KeyPair<felt252, felt252> {
    StarkCurveKeyPairImpl::from_secret_key('PRIVATE_KEY_1')
}
pub fn KEY_PAIR_2() -> KeyPair<felt252, felt252> {
    StarkCurveKeyPairImpl::from_secret_key('PRIVATE_KEY_2')
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
pub fn OPERATOR() -> ContractAddress {
    contract_address_const::<'OPERATOR'>()
}

pub fn COLLATERAL_TIMELY_DATA() -> CollateralTimelyData {
    CollateralTimelyData {
        version: COLLATERAL_VERSION,
        price: PRICE_1(),
        last_price_update: Time::now(),
        next: Option::None,
    }
}


pub fn SYNTHETIC_CONFIG() -> SyntheticConfig {
    SyntheticConfig {
        version: SYNTHETIC_VERSION,
        resolution: SYNTHETIC_RESOLUTION,
        name: SYNTHETIC_NAME,
        is_active: true,
        risk_factor: RISK_FACTOR_1(),
        quorum: SYNTHETIC_QUORUM,
    }
}

pub fn SYNTHETIC_TIMELY_DATA() -> SyntheticTimelyData {
    SyntheticTimelyData {
        version: SYNTHETIC_VERSION,
        price: PRICE_1(),
        // Pass non default timestamp.
        last_price_update: Time::now().add(delta: Time::seconds(count: 1)),
        funding_index: Zero::zero(),
        next: Option::None,
    }
}


pub const UPGRADE_DELAY: u64 = 5_u64;
/// 1 day in seconds.
pub const MAX_PRICE_INTERVAL: TimeDelta = TimeDelta { seconds: 86400 };
/// 1 day in seconds.
pub const MAX_FUNDING_INTERVAL: TimeDelta = TimeDelta { seconds: 86400 };
pub const MAX_FUNDING_RATE: u32 = 5;
pub const COLLATERAL_QUORUM: u8 = 0;
pub const COLLATERAL_QUANTUM: u64 = 1;
pub const SYNTHETIC_NAME: felt252 = 'SYNTHETIC_NAME';
pub const SYNTHETIC_QUORUM: u8 = 1;
pub const SYNTHETIC_RESOLUTION: u64 = 1_000_000_000;
pub const INITIAL_SUPPLY: u256 = 10_000_000_000_000_000;
pub const WITHDRAW_AMOUNT: i64 = 1000;
pub const DEPOSIT_AMOUNT: i64 = 10;
pub const TRANSFER_AMOUNT: i64 = 1000;
pub const COLLATERAL_BALANCE_AMOUNT: i64 = 2000;
pub const SYNTHETIC_BALANCE_AMOUNT: i64 = 2000;
pub const CONTRACT_INIT_BALANCE: u64 = 1_000_000_000;
pub const USER_INIT_BALANCE: u64 = 100_000_000;

pub const POSITION_ID_1: PositionId = PositionId { value: 2 };
pub const POSITION_ID_2: PositionId = PositionId { value: 3 };

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
pub fn SYNTHETIC_ASSET_ID_4() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_4"))
}
pub fn SYNTHETIC_ASSET_ID_5() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_5"))
}

/// Risk factors
pub fn RISK_FACTOR_1() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
pub fn RISK_FACTOR_2() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
pub fn RISK_FACTOR_3() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
pub fn RISK_FACTOR_4() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
pub fn RISK_FACTOR_5() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
/// Prices
pub fn PRICE_1() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
pub fn PRICE_2() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
pub fn PRICE_3() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
pub fn PRICE_4() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
pub fn PRICE_5() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
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
