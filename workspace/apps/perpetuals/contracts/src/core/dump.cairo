//! State-dump interface for replicating a live `Core` deployment's
//! state (e.g. across chains): a read-only export surface. All entrypoints are
//! read-only views, batched so a full dump takes as few calls as possible:
//!
//!  - `export_config()` — the ENTIRE config plane in ONE call: every scalar of
//!    every component, all assets (ids enumerated on-chain), and the external
//!    component registry (fixed key set).
//!  - `export_positions(ids)` — raw position dumps, one call per page of ids.
//!  - `export_keyed(keys)` — every event-keyed map (deposits, fulfillment,
//!    oracle, vaults, deposit limits) in one call per page of keys.
//!
//! Total dump = 1 + ceil(positions/page) + ceil(keyed/page) calls. Page size is
//! bounded by the node's per-call step limit (each storage slot is one
//! `storage_read` syscall), not by this code.
//!
//! KEY DISCOVERY. Asset ids need no input keys: `export_assets` enumerates the
//! `timely_data` `IterableMap`, and every registration path (synthetic, vault
//! share, spot) writes a `timely_data` entry alongside `asset_config`, while no
//! path ever removes one — deactivation only flips `asset_config.status` to
//! INACTIVE. Deactivated assets therefore stay in the dump. (Collateral is not
//! in these maps at all; it round-trips via the `AssetsDump` scalars.) All
//! other key sets — `export_positions` ids and every `export_keyed` field — are
//! NOT enumerable on-chain (plain `Map`s store no key list): the off-chain
//! copier discovers them from events or an application snapshot.
//!
//! NOTE ON SCOPE: the `Core` class already sits near Starknet's max class size,
//! so only `IDump` (positions + core scalars) is embedded in `Core`
//! itself. The rest of the surface (`IDumpExtra`) is hosted by the
//! dedicated storage-compatible `DumpCore` class swapped in via
//! `replace_to` (see dump_core.cairo), which embeds BOTH interfaces —
//! each method is declared in exactly one interface, so the selectors seen by
//! a driver written against `Core`'s subset are the same by construction.
//!
//! Not covered here: request-approval statuses (`approved_requests`) — the
//! upstream component keeps its storage and read impls private, so they are
//! read per-hash via `get_request_status` on the live Core class (batch at the
//! JSON-RPC level); `forced_action_requests` needs raw `starknet_getStorageAt`.

use perpetuals::core::components::assets::interface::AssetsDump;
use perpetuals::core::components::deposit::interface::DepositStatus;
use perpetuals::core::components::positions::interface::PositionDump;
use perpetuals::core::components::vaults::types::VaultConfig;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starknet::{ClassHash, ContractAddress};
use starkware_utils::signature::stark::{HashType, PublicKey};
use starkware_utils::time::time::{TimeDelta, Timestamp};

/// Core-module scalars with no getters (the treasury address is readable via
/// `get_treasury_address`, but is included in `ConfigDump` anyway).
#[derive(Drop, Serde)]
pub struct CoreDumpScalars {
    pub forced_action_timelock: TimeDelta,
    pub premium_cost: u64,
    pub forced_actions_enabled: bool,
    pub interest_divergence: i64,
}

/// One entry of the external-component registry (both underlying maps).
#[derive(Drop, Serde)]
pub struct ExternalComponentEntry {
    pub component_type: felt252,
    pub registered_class_hash: ClassHash,
    pub registered_at: Timestamp,
    pub implementation: ClassHash,
}

/// The entire config plane of the contract — everything that is not keyed by a
/// non-enumerable map key — returned by a single `export_config()` call.
#[derive(Drop, Serde)]
pub struct ConfigDump {
    pub operator_nonce: u64,
    pub exchange_time: Timestamp,
    pub last_time_of_exchange_time_update: Timestamp,
    pub paused: bool,
    pub deposit_cancel_delay: TimeDelta,
    pub max_interest_rate_per_sec: u32,
    pub treasury_address: ContractAddress,
    pub core: CoreDumpScalars,
    pub assets: AssetsDump,
    /// One entry per fixed component-type key (8 known constants).
    pub external_components: Array<ExternalComponentEntry>,
}

/// Input key sets for `export_keyed` — one page of keys per field, discovered
/// off-chain from events. Fields are independent; unused ones may be empty.
#[derive(Drop, Serde)]
pub struct KeySets {
    pub deposit_hashes: Array<HashType>,
    pub fulfillment_hashes: Array<HashType>,
    pub oracle_entries: Array<(AssetId, PublicKey)>,
    pub vault_asset_ids: Array<AssetId>,
    pub vault_position_ids: Array<PositionId>,
    pub vault_limit_override_position_ids: Array<PositionId>,
    pub deposit_limit_tokens: Array<ContractAddress>,
}

/// Output of `export_keyed` — each array is index-aligned with the
/// corresponding `KeySets` field.
#[derive(Drop, Serde)]
pub struct KeyedDump {
    pub deposit_statuses: Array<DepositStatus>,
    pub fulfillments: Array<u64>,
    pub oracle_values: Array<felt252>,
    pub vaults_by_asset: Array<VaultConfig>,
    pub vaults_by_position: Array<VaultConfig>,
    pub vault_limit_overrides: Array<u32>,
    pub max_deposits: Array<Option<u256>>,
}

/// The subset that fits inside `Core` next to the trading logic: the raw
/// position dump (whose data has no other read path — `get_position_assets`
/// returns funding-adjusted, not raw, balances and omits owner keys/flags)
/// plus the core scalars without getters.
#[starknet::interface]
pub trait IDump<TContractState> {
    fn export_positions(
        self: @TContractState, position_ids: Array<PositionId>,
    ) -> Array<PositionDump>;
    fn export_core_scalars(self: @TContractState) -> CoreDumpScalars;
}

/// The rest of the export surface, hosted only by `DumpCore` (which
/// embeds `IDump` + `IDumpExtra`; the two are disjoint, so every
/// method has exactly one declaration and drivers written against `Core`'s
/// subset work unchanged).
#[starknet::interface]
pub trait IDumpExtra<TContractState> {
    fn export_config(self: @TContractState) -> ConfigDump;
    fn export_keyed(self: @TContractState, keys: KeySets) -> KeyedDump;
}
