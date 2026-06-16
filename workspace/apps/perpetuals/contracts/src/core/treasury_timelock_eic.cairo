//! External Initializer Contract (EIC) that configures the treasury's protection-limit timelock
//! parameters as part of a class upgrade.
//!
//! The `reset_cooldown` and `change_timelock` storage fields were introduced together with the
//! treasury timelock feature and are written only by the constructor. A treasury that was deployed
//! before the feature therefore has both fields defaulting to zero after a `replace_class` upgrade
//! (the constructor does not run on upgrades), which would disable the manual-reset cooldown and
//! let protection-limit percent changes apply with no delay — defeating the timelock.
//!
//! This EIC is run via the `ReplaceabilityComponent` during the upgrade (a library call into the
//! treasury's storage) and sets both fields to one day. It takes no init data.

#[starknet::contract]
mod TreasuryTimelockEIC {
    use starknet::storage::StoragePointerWriteAccess;
    use starkware_utils::components::replaceability::interface::IEICInitializable;
    use starkware_utils::constants::DAY;
    use starkware_utils::time::time::TimeDelta;

    /// The value configured on upgrade for both the manual-reset cooldown and the protection-limit
    /// change timelock: one day.
    const TIMELOCK: TimeDelta = TimeDelta { seconds: DAY };

    // Mirrors `ProtocolTreasury`'s top-level timelock storage. The field names and types must match
    // exactly so that, during the upgrade library call, these writes land on the same storage slots
    // as the treasury's own `reset_cooldown` / `change_timelock` fields.
    #[storage]
    struct Storage {
        reset_cooldown: TimeDelta,
        change_timelock: TimeDelta,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            // This EIC hardcodes the timelock values, so it expects no init data.
            assert(eic_init_data.is_empty(), 'EIC_INIT_DATA_NOT_EMPTY');
            self.reset_cooldown.write(TIMELOCK);
            self.change_timelock.write(TIMELOCK);
        }
    }
}
