//! EIC that sets the treasury's protection-limit timelock params on upgrade: reset cooldown = 1
//! day, change-percent timelock = 12 hours. Takes no init data.

#[starknet::contract]
mod TreasuryTimelockEIC {
    use starknet::storage::StoragePointerWriteAccess;
    use starkware_utils::components::replaceability::interface::IEICInitializable;
    use starkware_utils::constants::{DAY, HOUR};
    use starkware_utils::time::time::TimeDelta;

    const RESET_COOLDOWN: TimeDelta = TimeDelta { seconds: DAY };
    const CHANGE_TIMELOCK: TimeDelta = TimeDelta { seconds: 12 * HOUR };

    // Field names/types must match `ProtocolTreasury` so the upgrade library call hits the same
    // slots.
    #[storage]
    struct Storage {
        reset_cooldown: TimeDelta,
        change_timelock: TimeDelta,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            assert(eic_init_data.is_empty(), 'EIC_INIT_DATA_NOT_EMPTY');
            self.reset_cooldown.write(RESET_COOLDOWN);
            self.change_timelock.write(CHANGE_TIMELOCK);
        }
    }
}
