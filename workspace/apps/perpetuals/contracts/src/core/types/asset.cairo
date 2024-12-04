pub mod collateral;
pub mod synthetic;

#[derive(Drop, Copy, Serde, Hash, starknet::Store)]
pub struct AssetId {
    pub value: felt252,
}
