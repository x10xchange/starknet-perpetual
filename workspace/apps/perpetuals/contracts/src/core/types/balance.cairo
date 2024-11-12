#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Balance {
    pub value: i128
}
