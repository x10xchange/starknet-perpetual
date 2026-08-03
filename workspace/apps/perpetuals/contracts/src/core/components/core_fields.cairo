/// Shared definition of `Core`'s contract-level storage fields.
///
/// `Core` and `DumpCore` (see core/dump_core.cairo) must address the
/// exact same storage slots. Component substorage is flattened under
/// `#[substorage(v0)]` — a member's storage address is derived from the member
/// name alone (`sn_keccak(<member_name>)`), with the embedding field name
/// playing no part — so hosting these fields in one shared component keeps the
/// two classes structurally in sync: a rename or retype propagates to both, and
/// the member addresses are identical to when these fields were declared
/// directly on `Core`. `test_core_fields_storage_addresses` asserts the raw
/// slot addresses, so a layout-breaking change to this struct fails CI.
#[starknet::component]
pub mod CoreFieldsComponent {
    use starkware_utils::time::time::TimeDelta;
    use treasury::interface::ITreasuryDispatcher;

    /// Members are `pub` deliberately: this component is a shared
    /// storage-layout definition, not an encapsulation boundary. It has no
    /// invariants of its own, and its only embedders (`Core`, `DumpCore`)
    /// own these fields outright.
    #[storage]
    pub struct Storage {
        pub treasury: ITreasuryDispatcher,
        // Forced action parameters:
        // Timelock before forced actions can be executed.
        pub forced_action_timelock: TimeDelta,
        // Cost for executing forced actions.
        pub premium_cost: u64,
        // Whether the new escape hatch logic is enabled.
        // Off by default to be enabled one time in the future.
        pub forced_actions_enabled: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}
}
