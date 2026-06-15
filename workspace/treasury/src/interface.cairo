use starknet::ContractAddress;
use starkware_utils::time::time::{TimeDelta, Timestamp};
use treasury::types::PendingPercentChange;

#[starknet::interface]
pub trait ITreasury<TState> {
    fn get_perps_contract(self: @TState) -> ContractAddress;
    fn deposit_into(ref self: TState, collateral_address: ContractAddress, amount: u256);
    fn withdraw_from(ref self: TState, collateral_address: ContractAddress, amount: u256);
    /// Re-snapshots the protection limit for `collateral_address`. Callable at most once per
    /// `RESET_PROTECTION_COOLDOWN` (one day) per collateral.
    fn reset_protection_limit(ref self: TState, collateral_address: ContractAddress);
    /// Records a pending change to the protection-limit percent. The change does not take effect
    /// until `apply_protection_limit_percent_change` is called after the timelock has elapsed.
    /// Re-requesting overwrites any existing pending change and restarts the timelock.
    fn request_protection_limit_percent_change(
        ref self: TState, collateral_address: ContractAddress, percent: u64,
    );
    /// Applies a previously requested protection-limit percent change once its timelock has passed.
    fn apply_protection_limit_percent_change(ref self: TState, collateral_address: ContractAddress);
    /// Cancels a pending protection-limit percent change.
    fn cancel_protection_limit_percent_change(
        ref self: TState, collateral_address: ContractAddress,
    );
    /// Returns the pending protection-limit percent change for `collateral_address`.
    /// `applicable_at == 0` means there is no pending change.
    fn get_pending_protection_limit_change(
        self: @TState, collateral_address: ContractAddress,
    ) -> PendingPercentChange;
    /// Returns the timestamp of the last manual reset for `collateral_address` (0 if never reset).
    fn get_last_protection_reset_at(
        self: @TState, collateral_address: ContractAddress,
    ) -> Timestamp;
    /// Returns the minimum cooldown between two manual `reset_protection_limit` calls.
    fn get_reset_cooldown(self: @TState) -> TimeDelta;
    /// Returns the timelock that must elapse between requesting and applying a percent change.
    fn get_protection_limit_timelock(self: @TState) -> TimeDelta;
}
