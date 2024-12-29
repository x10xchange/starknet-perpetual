use contracts_commons::types::fixed_two_decimal::{FixedTwoDecimal, FixedTwoDecimalTrait};
use contracts_commons::types::time::time::TimeDelta;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
use perpetuals::core::types::price::{Price, PriceTrait, TWO_POW_28};
use snforge_std::signature::KeyPair;
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use starknet::{ContractAddress, contract_address_const};


pub fn KEY_PAIR() -> KeyPair<felt252, felt252> {
    StarkCurveKeyPairImpl::from_secret_key('PRIVATE_KEY')
}
pub fn COLLATERAL_OWNER() -> ContractAddress nopanic {
    contract_address_const::<'COLLATERAL_OWNER'>()
}
pub fn POSITION_OWNER() -> ContractAddress nopanic {
    contract_address_const::<'POSITION_OWNER'>()
}
pub fn VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS() -> ContractAddress {
    contract_address_const::<'VALUE_RISK_CALCULATOR_ADDRESS'>()
}
pub fn TOKEN_ADDRESS() -> ContractAddress {
    contract_address_const::<'TOKEN_ADDRESS'>()
}
pub fn RISK_FACTOR() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
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

/// 1 day in seconds.
pub const PRICE_VALIDATION_INTERVAL: TimeDelta = TimeDelta { seconds: 86400 };
/// 1 day in seconds.
pub const FUNDING_VALIDATION_INTERVAL: TimeDelta = TimeDelta { seconds: 86400 };
pub const MAX_FUNDING_RATE: u32 = 5;
pub const COLLATERAL_DECIMALS: u8 = 6;
pub const COLLATERAL_QUORUM: u8 = 0;
pub const COLLATERAL_QUANTUM: u64 = 1_000_000_000;
pub const SYNTHETIC_DECIMALS: u8 = 6;
pub const SYNTHETIC_QUORUM: u8 = 1;
pub const SYNTHETIC_RESOLUTION: u64 = 1_000_000_000;
pub const INITIAL_SUPPLY: u256 = 10_000_000_000;
pub const WITHDRAW_AMOUNT: i64 = 1000;

pub const POSITION_ID: PositionId = PositionId { value: 'POSITION_ID' };

/// Assets IDs
pub fn ASSET_ID() -> AssetId {
    AssetIdTrait::new(value: selector!("asset_id"))
}
pub fn ASSET_ID_1() -> AssetId {
    AssetIdTrait::new(value: selector!("asset_id_1"))
}
pub fn ASSET_ID_2() -> AssetId {
    AssetIdTrait::new(value: selector!("asset_id_2"))
}
pub fn ASSET_ID_3() -> AssetId {
    AssetIdTrait::new(value: selector!("asset_id_3"))
}
pub fn ASSET_ID_4() -> AssetId {
    AssetIdTrait::new(value: selector!("asset_id_4"))
}
pub fn ASSET_ID_5() -> AssetId {
    AssetIdTrait::new(value: selector!("asset_id_5"))
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
pub fn PRICE() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
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
pub fn SYNTHETIC_NAME() -> ByteArray {
    "SYNTHETIC_NAME"
}
pub fn SYNTHETIC_SYMBOL() -> ByteArray {
    "SYN"
}
