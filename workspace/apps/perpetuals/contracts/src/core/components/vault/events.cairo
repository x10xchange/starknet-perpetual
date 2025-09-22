use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct VaultOpened {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub asset_id: AssetId,
}