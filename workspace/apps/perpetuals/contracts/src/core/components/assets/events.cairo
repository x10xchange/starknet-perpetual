use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct FundingTick {
    #[key]
    pub asset_id: AssetId,
    pub funding_index: FundingIndex,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct PriceTick {
    #[key]
    pub asset_id: AssetId,
    pub price: Price,
}
