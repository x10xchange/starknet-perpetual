pub const NAME: felt252 = 'Perpetuals';
pub const VERSION: felt252 = 'v0';

/// Recipient of every `migration_withdraw`: the operator withdraws to this address without a
/// signed `withdraw_request`.
pub const MIGRATION_WITHDRAWAL_RECIPIENT: felt252 =
    0x04e64b8c1126ff6a9b870664b6b7a82e8b729301aa2b49682d819f561e7823bd;
