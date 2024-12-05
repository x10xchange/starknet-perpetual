use contracts_commons::types::time::Timestamp;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::{Fee, Signature};

pub const VERSION: u8 = 0;

pub struct Order {
    pub version: u8,
    pub signature: Signature,
    // OrderMessage
    pub position_id: felt252,
    pub base_type: AssetId,
    pub quote_type: AssetId,
    pub amount_base: i128,
    pub amount_quote: i128,
    pub fee_token_type: AssetId,
    pub fee: Fee,
    pub expiration: Timestamp,
    pub salt: felt252,
}
