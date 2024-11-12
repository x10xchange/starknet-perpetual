use perpetuals::core::types::FundingIndex;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;

// Collateral asset in a position.
// - balance: The amount of the collateral asset held in the position.
// - next: The next collateral asset id in the position.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct CollateralNode {
    pub balance: Balance,
    pub next: Option<AssetId>
}

// Synthetic asset in a position.
// - balance: The amount of the synthetic asset held in the position.
// - funding_index: The funding index at the time of the last update.
// - next: The next synthetic asset id in the position.
pub struct SyntheticNode {
    pub balance: Balance,
    pub funding_index: FundingIndex,
    pub next: Option<AssetId>
}
