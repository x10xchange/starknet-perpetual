use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use perpetuals::core::types::funding_index::FundingIndex;
use starknet::{ContractAddress, contract_address_const};

pub const VERSION: u8 = 0;

pub fn SYNTHETIC_ADDRESS() -> ContractAddress {
    contract_address_const::<'synthetic'>()
}

#[derive(Drop, Copy, starknet::Store, Serde)]
pub struct Asset {
    pub version: u8,
    pub id: AssetId,
    pub address: ContractAddress,
    pub decimals: u8,
    pub is_active: bool,
    pub last_funding_index: FundingIndex,
    pub name: felt252,
    pub oracle_price: u64,
    pub quorum: u8,
    pub risk_factor: FixedTwoDecimal,
}

#[generate_trait]
pub impl AssetImpl of AssetTrait {
    fn is_active(self: @Asset) -> bool {
        *self.is_active
    }
    fn is_synthetic(self: @Asset) -> bool {
        *self.address == SYNTHETIC_ADDRESS()
    }
}

#[derive(Drop, Copy, PartialEq, Serde, Hash, starknet::Store)]
pub struct AssetId {
    pub value: felt252,
}
