use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;

pub const AMOUNT_TOO_LARGE: felt252 = 'AMOUNT_TOO_LARGE';
pub const TRANSFER_EXPIRED: felt252 = 'TRANSFER_EXPIRED';
pub const DIFFERENT_BASE_ASSET_IDS: felt252 = 'DIFFERENT_BASE_ASSET_IDS';
pub const DIFFERENT_QUOTE_ASSET_IDS: felt252 = 'DIFFERENT_QUOTE_ASSET_IDS';
pub const INSUFFICIENT_FUNDS: felt252 = 'INSUFFICIENT_FUNDS';
pub const INVALID_DELEVERAGE_BASE_CHANGE: felt252 = 'INVALID_DELEVERAGE_BASE_CHANGE';
pub const INVALID_FUNDING_TICK_LEN: felt252 = 'INVALID_FUNDING_TICK_LEN';
pub const INVALID_NEGATIVE_FEE: felt252 = 'INVALID_NEGATIVE_FEE';
pub const INVALID_NON_SYNTHETIC_ASSET: felt252 = 'INVALID_NON_SYNTHETIC_ASSET';
pub const INVALID_OWNER_SIGNATURE: felt252 = 'INVALID_ACCOUNT_OWNER_SIGNATURE';
pub const INVALID_POSITION: felt252 = 'INVALID_POSITION';
pub const INVALID_PUBLIC_KEY: felt252 = 'INVALID_PUBLIC_KEY';
pub const INVALID_TRADE_ACTUAL_BASE_SIGN: felt252 = 'INVALID_TRADE_ACTUAL_BASE_SIGN';
pub const INVALID_TRADE_ACTUAL_QUOTE_SIGN: felt252 = 'INVALID_TRADE_ACTUAL_QUOTE_SIGN';
pub const INVALID_TRADE_QUOTE_AMOUNT_SIGN: felt252 = 'INVALID_TRADE_QUOTE_AMOUNT_SIGN';
pub const INVALID_TRADE_WRONG_AMOUNT_SIGN: felt252 = 'INVALID_TRADE_WRONG_AMOUNT_SIGN';
pub const INVALID_ZERO_AMOUNT: felt252 = 'INVALID_ZERO_AMOUNT';
pub const INVALID_TRANSFER_AMOUNT: felt252 = 'INVALID_TRANSFER_AMOUNT';
pub const NO_OWNER_ACCOUNT: felt252 = 'NO_OWNER_ACCOUNT';
pub const POSITION_ALREADY_EXISTS: felt252 = 'POSITION_ALREADY_EXISTS';
pub const POSITION_HAS_OWNER_ACCOUNT: felt252 = 'POSITION_HAS_OWNER_ACCOUNT';
pub const POSITION_IS_NOT_DELEVERAGABLE: felt252 = 'POSITION_IS_NOT_DELEVERAGABLE';
pub const POSITION_IS_NOT_FAIR_DELEVERAGE: felt252 = 'POSITION_IS_NOT_FAIR_DELEVERAGE';
pub const POSITION_IS_NOT_HEALTHIER: felt252 = 'POSITION_IS_NOT_HEALTHIER';
pub const POSITION_IS_NOT_LIQUIDATABLE: felt252 = 'POSITION_IS_NOT_LIQUIDATABLE';
pub const POSITION_UNHEALTHY: felt252 = 'POSITION_UNHEALTHY';
pub const SET_POSITION_OWNER_EXPIRED: felt252 = 'SET_POSITION_OWNER_EXPIRED';
pub const SET_PUBLIC_KEY_EXPIRED: felt252 = 'SET_PUBLIC_KEY_EXPIRED';
pub const WITHDRAW_EXPIRED: felt252 = 'WITHDRAW_EXPIRED';
pub const CALLER_IS_NOT_OWNER_ACCOUNT: felt252 = 'CALLER_IS_NOT_OWNER_ACCOUNT';
pub const APPLY_DIFF_MISMATCH: felt252 = 'APPLY_DIFF_MISMATCH';

pub fn fulfillment_exceeded_err(position_id: PositionId) -> ByteArray {
    format!("FULFILLMENT_EXCEEDED position_id: {:?}", position_id)
}

pub fn invalid_funding_rate_err(synthetic_id: AssetId) -> ByteArray {
    format!("INVALID_FUNDING_RATE synthetic_id: {:?}", synthetic_id)
}

pub fn order_expired_err(position_id: PositionId) -> ByteArray {
    format!("ORDER_EXPIRED position_id: {:?}", position_id)
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
