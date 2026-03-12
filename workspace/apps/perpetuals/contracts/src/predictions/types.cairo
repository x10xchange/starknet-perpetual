use starknet::storage::Map;

// Converts base token units (10^-6 for USDC) to dp3 (10^-3).
pub const BASE_TO_DP3_DIVISOR: u64 = 1000;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct MarketPosition {
    pub amount: u64,
}

#[starknet::storage_node]
pub struct Account {
    pub owning_key: felt252,
    pub collateral: u64,
    pub tokens: Map<felt252, MarketPosition>,
}

#[generate_trait]
pub impl Dp3Impl of Dp3Trait {
    /// Converts a quantized amount to dp3 given the collateral quantum.
    /// quantized * quantum gives base token units, then / BASE_TO_DP3_DIVISOR gives dp3.
    fn quantized_to_dp3(quantized_amount: u64, collateral_quantum: u64) -> u64 {
        (quantized_amount * collateral_quantum) / BASE_TO_DP3_DIVISOR
    }

    /// Converts a dp3 amount back to quantized given the collateral quantum.
    fn dp3_to_quantized(dp3_amount: u64, collateral_quantum: u64) -> u64 {
        (dp3_amount * BASE_TO_DP3_DIVISOR) / collateral_quantum
    }
}
