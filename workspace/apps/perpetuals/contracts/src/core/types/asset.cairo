pub mod collateral;
pub mod synthetic;

#[derive(Copy, Debug, Drop, Hash, Serde, starknet::Store)]
pub struct AssetId {
    pub value: felt252,
}
