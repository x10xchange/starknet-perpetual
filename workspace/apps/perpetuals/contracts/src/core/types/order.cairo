use contracts_commons::types::time::Timestamp;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::{Fee, Signature};

pub struct Order {
    pub order_type: OrderType,
    pub base_type: AssetId,
    pub quote_type: AssetId,
    pub amount_base: Balance,
    pub amount_quote: Balance,
    pub fee_token_type: AssetId,
    pub fee: Fee,
    pub expiration: Timestamp,
    pub nonce: felt252,
    pub signature: Signature,
    pub position_id: felt252,
}

pub enum OrderType {
    Limit,
}
