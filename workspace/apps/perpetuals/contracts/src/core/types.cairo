use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::TimeStamp;
use starknet::ContractAddress;


#[derive(Drop, Serde, Hash, starknet::Store)]
pub struct AssetId {
    pub value: felt252
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Balance {
    pub value: i64
}

// Collateral asset in a position.
// - balance: The amount of the collateral asset held in the position.
// - next: The next collateral asset id in the position.
#[derive(Drop, Serde, starknet::Store)]
pub struct CollateralNode {
    pub balance: Balance,
    pub next: AssetId
}

pub struct Fee {
    pub value: u64,
}

pub struct FundingIndex {
    pub value: i64
}

pub type Nonce = felt252;

pub struct Order {
    pub order_type: OrderType,
    pub base_type: AssetId,
    pub quote_type: AssetId,
    pub amount_base: Balance,
    pub amount_quote: Balance,
    // for X10 we can choose how to pay the fee
    // fee_token_type: AssetId,
    pub fee: Fee,
    pub expiration: TimeStamp,
    pub nonce: Nonce,
    pub signature: Signature,
    pub position_id: PositionId
}

pub enum OrderType {
    Limit: u8,
}

#[derive(Drop, Serde, Hash)]
pub struct PositionId {
    pub value: felt252
}

pub type RiskFactor = FixedTwoDecimal;

pub type Signature = Array<felt252>;

// Synthetic asset in a position.
// - balance: The amount of the synthetic asset held in the position.
// - funding_index: The funding index at the time of the last update.
// - next: The next synthetic asset id in the position.
pub struct SyntheticNode {
    pub balance: Balance,
    pub funding_index: FundingIndex,
    pub next: AssetId
}

#[derive(Drop, Serde)]
pub struct PositionData {
    pub version: u8,
    pub owner: ContractAddress,
    pub asset_entries: Span<AssetEntry>
}

#[derive(Drop, Serde)]
pub struct AssetEntry {
    pub id: AssetId,
    pub value: Balance,
    pub price: u64,
    pub risk_factor: RiskFactor
}
