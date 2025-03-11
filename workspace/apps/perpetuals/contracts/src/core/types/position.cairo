use perpetuals::core::types::asset::synthetic::SyntheticAsset;
use perpetuals::core::types::asset::{Asset, AssetDiffEnriched, AssetId};
use perpetuals::core::types::balance::{Balance, BalanceDiff};
use starknet::ContractAddress;
use starknet::storage::{Mutable, StoragePath, StoragePointerReadAccess};
use starkware_utils::iterable_map::{
    IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
};
use starkware_utils::types::PublicKey;

pub const POSITION_VERSION: u8 = 1;

#[starknet::storage_node]
pub struct Position {
    pub version: u8,
    pub owner_account: Option<ContractAddress>,
    pub owner_public_key: PublicKey,
    pub collateral_balance: Balance,
    pub synthetic_assets: IterableMap<AssetId, SyntheticAsset>,
}


#[derive(Copy, Debug, Drop, Hash, PartialEq, Serde)]
pub struct PositionId {
    pub value: u32,
}

#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiff {
    pub collateral: Balance,
    pub synthetic: Option<(AssetId, Balance)>,
}

pub fn create_position_diff(
    collateral_diff: Balance, synthetic_id: AssetId, synthetic_diff: Balance,
) -> PositionDiff {
    PositionDiff {
        collateral: collateral_diff, synthetic: Option::Some((synthetic_id, synthetic_diff)),
    }
}
pub fn create_collateral_position_diff(collateral_diff: Balance) -> PositionDiff {
    PositionDiff { collateral: collateral_diff, synthetic: Option::None }
}

#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiffEnriched {
    pub collateral: BalanceDiff,
    pub synthetic: Option<AssetDiffEnriched>,
}

pub type PositionData = Span<Asset>;
pub type UnchangedAssets = PositionData;


pub impl U32IntoPositionId of Into<u32, PositionId> {
    fn into(self: u32) -> PositionId {
        PositionId { value: self }
    }
}

pub impl PositionIdIntoU32 of Into<PositionId, u32> {
    fn into(self: PositionId) -> u32 {
        self.value
    }
}

#[generate_trait]
pub impl PositionImpl of PositionTrait {
    fn get_owner_account(self: StoragePath<Position>) -> Option<ContractAddress> {
        self.owner_account.read()
    }

    fn get_owner_public_key(self: StoragePath<Position>) -> PublicKey {
        self.owner_public_key.read()
    }
    fn get_version(self: StoragePath<Position>) -> u8 {
        self.version.read()
    }
}

#[generate_trait]
pub impl PositionMutableImpl of PositionMutableTrait {
    fn get_owner_account(self: StoragePath<Mutable<Position>>) -> Option<ContractAddress> {
        self.owner_account.read()
    }

    fn get_owner_public_key(self: StoragePath<Mutable<Position>>) -> PublicKey {
        self.owner_public_key.read()
    }
    fn get_version(self: StoragePath<Mutable<Position>>) -> u8 {
        self.version.read()
    }
}
