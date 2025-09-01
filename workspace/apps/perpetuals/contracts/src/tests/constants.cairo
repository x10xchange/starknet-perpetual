use core::num::traits::Pow;
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
use perpetuals::core::types::position::PositionId;
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use starknet::ContractAddress;
use starkware_utils::constants::{DAY, MINUTE, WEEK};
use starkware_utils::time::time::TimeDelta;


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
pub fn COLLATERAL_OWNER() -> ContractAddress {
    'COLLATERAL_OWNER'.try_into().unwrap()
}
pub fn POSITION_OWNER_1() -> ContractAddress {
    'POSITION_OWNER_1'.try_into().unwrap()
}
pub fn POSITION_OWNER_2() -> ContractAddress {
    'POSITION_OWNER_2'.try_into().unwrap()
}
pub fn TOKEN_ADDRESS() -> ContractAddress {
    'TOKEN_ADDRESS'.try_into().unwrap()
}
pub fn GOVERNANCE_ADMIN() -> ContractAddress {
    'GOVERNANCE_ADMIN'.try_into().unwrap()
}
pub fn APP_ROLE_ADMIN() -> ContractAddress {
    'APP_ROLE_ADMIN'.try_into().unwrap()
}
pub fn APP_GOVERNOR() -> ContractAddress {
    'APP_GOVERNOR'.try_into().unwrap()
}
pub fn OPERATOR() -> ContractAddress {
    'OPERATOR'.try_into().unwrap()
}

pub const UPGRADE_DELAY: u64 = 5_u64;
/// 1 day in seconds.
pub const MAX_PRICE_INTERVAL: TimeDelta = TimeDelta { seconds: DAY };
/// 1 day in seconds.
pub const MAX_FUNDING_INTERVAL: TimeDelta = TimeDelta { seconds: DAY };
/// 10 minutes in seconds.
pub const MAX_ORACLE_PRICE_VALIDITY: TimeDelta = TimeDelta { seconds: 10 * MINUTE };
pub const CANCEL_DELAY: TimeDelta = TimeDelta { seconds: WEEK };
pub const MAX_FUNDING_RATE: u32 = 35792; // Which is ~3% in an hour.
pub const COLLATERAL_QUORUM: u8 = 0;
pub const COLLATERAL_QUANTUM: u64 = 1_000;
pub const SYNTHETIC_QUORUM: u8 = 1;
pub const SYNTHETIC_RESOLUTION_FACTOR: u64 = 1_000_000_000;
pub const INITIAL_SUPPLY: u256 = 10_000_000_000_000_000;
pub const WITHDRAW_AMOUNT: u64 = 1000;
pub const DEPOSIT_AMOUNT: u64 = 10;
pub const TRANSFER_AMOUNT: u64 = 1000;
pub const COLLATERAL_BALANCE_AMOUNT: i64 = 2000;
pub const SYNTHETIC_BALANCE_AMOUNT: i64 = 20;
pub const CONTRACT_INIT_BALANCE: u128 = 1_000_000_000;
pub const USER_INIT_BALANCE: u128 = 10_000_000_000;

pub const POSITION_ID_1: PositionId = PositionId { value: 2 };
pub const POSITION_ID_2: PositionId = PositionId { value: 3 };

pub const ORACLE_A_NAME: felt252 = 'ORCLA';
pub const ORACLE_B_NAME: felt252 = 'ORCLB';

/// Risk factors
pub const RISK_FACTOR: u16 = 500;

/// Prices
pub const ORACLE_PRICE: u128 = 10_u128.pow(23);

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
