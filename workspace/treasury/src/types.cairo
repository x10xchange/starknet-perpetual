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
