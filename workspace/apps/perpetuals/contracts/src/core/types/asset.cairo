use perpetuals::core::types::{FundingIndex, RiskFactor};
use starknet::{ContractAddress, contract_address_const};

#[derive(Drop, starknet::Store, Serde)]
pub struct Asset {
    version: u8,
    id: AssetId,
    address: ContractAddress,
    decimals: u8,
    is_active: bool,
    last_funding_index: FundingIndex,
    name: felt252,
    oracle_price: u64,
    quorum: u8,
    risk_factor: RiskFactor
}

#[generate_trait]
pub impl AssetImpl of AssetTrait {
    fn is_active(self: @Asset) -> bool {
        *self.is_active
    }
    fn is_synthetic(self: @Asset) -> bool {
        *self.address == contract_address_const::<'synthetic'>()
    }
}

#[derive(Drop, Copy, PartialEq, Serde, Hash, starknet::Store)]
pub struct AssetId {
    pub value: felt252
}
