pub mod asset;
pub mod balance;
pub mod funding;
pub(crate) mod order;
pub mod price;
pub(crate) mod set_owner_account;
pub mod set_public_key;
pub mod transfer;
pub mod withdraw;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::price::Price;

pub type Signature = Span<felt252>;

#[derive(Copy, Debug, Drop, Hash, PartialEq, Serde)]
pub struct PositionId {
    pub value: u32,
}

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


#[derive(Copy, Debug, Drop, Hash, PartialEq, Serde)]
pub struct AssetAmount {
    pub asset_id: AssetId,
    pub amount: i64,
}

#[derive(Debug, Drop, Serde)]
pub struct PositionData {
    pub asset_entries: Span<AssetEntry>,
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct AssetEntry {
    pub id: AssetId,
    pub balance: Balance,
    pub price: Price,
    pub risk_factor: FixedTwoDecimal,
}

#[derive(Copy, Default, Drop, Serde)]
pub struct AssetDiffEntry {
    pub id: AssetId,
    pub before: Balance,
    pub after: Balance,
    pub price: Price,
    pub risk_factor: FixedTwoDecimal,
}

pub type PositionDiff = Span<AssetDiffEntry>;
