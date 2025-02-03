use contracts_commons::types::PublicKey;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct AddOracle {
    #[key]
    pub asset_id: AssetId,
    #[key]
    pub oracle_public_key: PublicKey,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct AddSynthetic {
    #[key]
    pub asset_id: AssetId,
    pub risk_factor: u8,
    pub resolution: u64,
    pub quorum: u8,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct AssetActivated {
    #[key]
    pub asset_id: AssetId,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct DeactivateSyntheticAsset {
    #[key]
    pub asset_id: AssetId,
}

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

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct RemoveOracle {
    #[key]
    pub asset_id: AssetId,
    #[key]
    pub oracle_public_key: PublicKey,
}
