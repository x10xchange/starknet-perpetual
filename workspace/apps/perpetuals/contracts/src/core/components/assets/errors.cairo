use perpetuals::core::types::asset::AssetId;

pub const ASSET_ALREADY_EXISTS: felt252 = 'ASSET_ALREADY_EXISTS';
pub const ASSET_NOT_EXISTS: felt252 = 'ASSET_NOT_EXISTS';
pub const BASE_ASSET_NOT_ACTIVE: felt252 = 'BASE_ASSET_NOT_ACTIVE';
pub const COLLATERAL_NOT_ACTIVE: felt252 = 'COLLATERAL_NOT_ACTIVE';
pub const COLLATERAL_NOT_EXISTS: felt252 = 'COLLATERAL_NOT_EXISTS';
pub const FUNDING_EXPIRED: felt252 = 'FUNDING_EXPIRED';
pub const SYNTHETIC_EXPIRED_PRICE: felt252 = 'SYNTHETIC_EXPIRED_PRICE';
pub const SYNTHETIC_NOT_ACTIVE: felt252 = 'SYNTHETIC_NOT_ACTIVE';
pub const SYNTHETIC_NOT_EXISTS: felt252 = 'SYNTHETIC_NOT_EXISTS';

pub fn invalid_funding_tick_err(synthetic_id: AssetId) -> ByteArray {
    format!("INVALID_FUNDING_TICK synthetic_id: {:?}", synthetic_id)
}
