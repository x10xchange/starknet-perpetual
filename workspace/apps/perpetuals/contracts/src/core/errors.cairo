use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;

pub const ALREADY_FULFILLED: felt252 = 'ALREADY_FULFILLED';
pub const AMOUNT_TOO_LARGE: felt252 = 'AMOUNT_TOO_LARGE';
pub const BASE_ASSET_NOT_ACTIVE: felt252 = 'BASE_ASSET_NOT_ACTIVE';
pub const COLLATERAL_EXPIRED_PRICE: felt252 = 'COLLATERAL_EXPIRED_PRICE';
pub const COLLATERAL_NOT_ACTIVE: felt252 = 'COLLATERAL_NOT_ACTIVE';
pub const COLLATERAL_NOT_EXISTS: felt252 = 'COLLATERAL_NOT_EXISTS';
pub const FACT_NOT_REGISTERED: felt252 = 'FACT_NOT_REGISTERED';
pub const FUNDING_EXPIRED: felt252 = 'FUNDING_EXPIRED';
pub const DIFFERENT_BASE_ASSET_IDS: felt252 = 'DIFFERENT_BASE_ASSET_IDS';
pub const DIFFERENT_QUOTE_ASSET_IDS: felt252 = 'DIFFERENT_QUOTE_ASSET_IDS';
pub const INVALID_DEPOSIT_AMOUNT: felt252 = 'INVALID_DEPOSIT_AMOUNT';
pub const INVALID_FUNDING_TICK: felt252 = 'INVALID_FUNDING_TICK';
pub const INVALID_FUNDING_TICK_LEN: felt252 = 'INVALID_FUNDING_TICK_LEN';
pub const INVALID_NEGATIVE_FEE: felt252 = 'INVALID_NEGATIVE_FEE';
pub const NO_OWNER_ACCOUNT: felt252 = 'NO_OWNER_ACCOUNT';
pub const INVALID_OWNER_SIGNATURE: felt252 = 'INVALID_ACCOUNT_OWNER_SIGNATURE';
pub const INVALID_POSITION: felt252 = 'INVALID_POSITION';
pub const INVALID_STARK_SIGNATURE: felt252 = 'INVALID_STARK_KEY_SIGNATURE';
pub const INVALID_TRADE_ACTUAL_BASE_SIGN: felt252 = 'INVALID_TRADE_ACTUAL_BASE_SIGN';
pub const INVALID_TRADE_ACTUAL_QUOTE_SIGN: felt252 = 'INVALID_TRADE_ACTUAL_QUOTE_SIGN';
pub const INVALID_TRADE_QUOTE_AMOUNT_SIGN: felt252 = 'INVALID_TRADE_QUOTE_AMOUNT_SIGN';
pub const INVALID_TRADE_WRONG_AMOUNT_SIGN: felt252 = 'INVALID_TRADE_WRONG_AMOUNT_SIGN';
pub const INVALID_WITHDRAW_AMOUNT: felt252 = 'INVALID_WITHDRAW_AMOUNT';
pub const POSITION_UNHEALTHY: felt252 = 'POSITION_UNHEALTHY';
pub const SYNTHETIC_EXPIRED_PRICE: felt252 = 'SYNTHETIC_EXPIRED_PRICE';
pub const SYNTHETIC_NOT_ACTIVE: felt252 = 'SYNTHETIC_NOT_ACTIVE';
pub const SYNTHETIC_NOT_EXISTS: felt252 = 'SYNTHETIC_NOT_EXISTS';
pub const WITHDRAW_EXPIRED: felt252 = 'WITHDRAW_EXPIRED';

pub fn fulfillment_exceeded_err(position_id: PositionId) -> ByteArray {
    format!("FULFILLMENT_EXCEEDED position_id: {:?}", position_id)
}

pub fn invalid_funding_tick_err(synthetic_id: AssetId) -> ByteArray {
    format!("INVALID_FUNDING_TICK synthetic_id: {:?}", synthetic_id)
}

pub fn position_not_healthy_nor_healthier(position_id: PositionId) -> ByteArray {
    format!("POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: {:?}", position_id)
}

pub fn trade_illegal_base_to_quote_ratio_err(position_id: PositionId) -> ByteArray {
    format!("TRADE_ILLEGAL_BASE_TO_QUOTE_RATIO position_id: {:?}", position_id)
}

pub fn trade_illegal_fee_to_quote_ratio_err(position_id: PositionId) -> ByteArray {
    format!("TRADE_ILLEGAL_FEE_TO_QUOTE_RATIO position_id: {:?}", position_id)
}

pub fn trade_order_expired_err(position_id: PositionId) -> ByteArray {
    format!("TRADE_ORDER_EXPIRED position_id: {:?}", position_id)
}

