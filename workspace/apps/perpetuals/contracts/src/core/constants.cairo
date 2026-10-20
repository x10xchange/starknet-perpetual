pub const NAME: felt252 = 'Perpetuals';
pub const VERSION: felt252 = 'v0';

/// Recipient of every `migration_withdraw`: the operator withdraws to this address without a
/// signed `withdraw_request`.
pub const MIGRATION_WITHDRAWAL_RECIPIENT: felt252 =
    0x04e64b8c1126ff6a9b870664b6b7a82e8b729301aa2b49682d819f561e7823bd;

/// Rhino.fi bridge used for deposits after the migration upgrade.
pub const RHINO_BRIDGE: felt252 =
    0x0259fec57cd26d27385cd8948d3693bbf26bed68ad54d7bdd1fdb901774ff0e8;
