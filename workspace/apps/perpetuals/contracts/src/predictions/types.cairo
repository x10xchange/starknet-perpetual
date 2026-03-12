use starknet::storage::Map;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct MarketPosition {
    pub amount: u64,
}

#[starknet::storage_node]
pub struct Account {
    pub owning_key: felt252,
    pub collateral: u64,
    pub tokens: Map<felt252, MarketPosition>,
}
