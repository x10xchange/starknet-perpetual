use starkware_utils::math::utils::mul_wide_and_floor_div;
use starkware_utils::time::time::{Time, Timestamp};

const PERCENT_SCALE: u128 = 1000;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ProtectionState {
    pub time_of_last_reset: Timestamp,
    pub amount_withdrawn_since_reset: u128,
    pub balance_at_last_reset: u128,
    pub max_allowed_withdrawal: u128,
}

/// A pending, timelocked change to a collateral's protection-limit percent.
/// `applicable_at == 0` (the storage default) means there is no pending change.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct PendingPercentChange {
    pub percent: u64,
    pub applicable_at: Timestamp,
}

/// New per-collateral governance state introduced alongside the timelock feature, kept in one
/// storage entry (separate from the pre-existing `protection` snapshot and
/// `protection_percent_override`
/// maps, whose layouts must stay unchanged for the deployed contract).
/// - `last_manual_reset_at == 0` means "never manually reset".
/// - `pending.applicable_at == 0` means "no pending change".
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ProtectionAdminState {
    pub last_manual_reset_at: Timestamp,
    pub pending: PendingPercentChange,
}

#[generate_trait]
pub impl ProtectionStateImpl of ProtectionStateTrait {
    fn new(balance: u128, percent: u64) -> ProtectionState {
        ProtectionState {
            time_of_last_reset: Time::now(),
            amount_withdrawn_since_reset: 0,
            balance_at_last_reset: balance,
            max_allowed_withdrawal: compute_max_withdrawal(balance, percent),
        }
    }
}

pub fn compute_max_withdrawal(balance: u128, percent: u64) -> u128 {
    mul_wide_and_floor_div(balance, percent.into() * 10, PERCENT_SCALE).expect('MUL_DIV_OVERFLOW')
}
