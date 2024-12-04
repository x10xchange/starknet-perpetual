use core::num::traits::Zero;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding_index::FundingIndex;

pub const VERSION: u8 = 0;
pub const HEAD_ASSET_ID: AssetId = AssetId { value: 'head' };

/// This is a trait for a node in a Storage Map.
/// head() returns first node of the Map.
/// head_asset_id() returns the asset_id of the first node in the Map.
pub trait Node<T, NEXT> {
    fn head() -> T;
    fn head_asset_id() -> NEXT;
}

/// Collateral asset in a position.
/// - balance: The amount of the collateral asset held in the position.
/// - next: The next collateral asset id in the position.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct CollateralNode {
    pub version: u8,
    pub balance: Balance,
    pub next: Option<AssetId>,
}

impl CollateralNodeImpl of Node<CollateralNode, AssetId> {
    fn head() -> CollateralNode {
        CollateralNode { version: VERSION, balance: Zero::zero(), next: Option::None }
    }
    fn head_asset_id() -> AssetId {
        HEAD_ASSET_ID
    }
}

/// Synthetic asset in a position.
/// - balance: The amount of the synthetic asset held in the position.
/// - funding_index: The funding index at the time of the last update.
/// - next: The next synthetic asset id in the position.
pub struct SyntheticNode {
    pub version: u8,
    pub balance: Balance,
    pub funding_index: FundingIndex,
    pub next: Option<AssetId>,
}

impl SyntheticNodeImpl of Node<SyntheticNode, AssetId> {
    fn head() -> SyntheticNode {
        SyntheticNode {
            version: VERSION,
            balance: Zero::zero(),
            funding_index: Zero::zero(),
            next: Option::None,
        }
    }
    fn head_asset_id() -> AssetId {
        HEAD_ASSET_ID
    }
}
