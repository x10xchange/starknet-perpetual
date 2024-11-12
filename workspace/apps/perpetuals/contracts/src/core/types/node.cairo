use perpetuals::core::types::FundingIndex;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;

pub const MARKER_ASSET_ID: AssetId = AssetId { value: 'marker' };

// Collateral asset in a position.
// - balance: The amount of the collateral asset held in the position.
// - next: The next collateral asset id in the position.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct CollateralNode {
    pub balance: Balance,
    pub next: Option<AssetId>
}

#[generate_trait]
pub impl CollateralNodeImpl of CollateralNodeTrait {
    fn marker() -> CollateralNode {
        CollateralNode { balance: Balance { value: 0 }, next: Option::None }
    }
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

#[generate_trait]
pub impl SyntheticNodeImpl of SyntheticNodeTrait {
    fn marker() -> SyntheticNode {
        SyntheticNode {
            balance: Balance { value: 0 },
            funding_index: FundingIndex { value: 0 },
            next: Option::None
        }
    }
}
