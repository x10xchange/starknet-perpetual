use perpetuals::core::types::asset::AssetId;

pub const HEAD_ASSET_ID: AssetId = AssetId { value: 'head' };

/// This is a trait for a node in a Storage Map.
/// head() returns first node of the Map.
/// head_asset_id() returns the asset_id of the first node in the Map.
pub trait Node<T> {
    fn head() -> T;
    fn head_asset_id() -> AssetId {
        HEAD_ASSET_ID
    }
}
