#[starknet::contract]
mod InitializeInterestRateEIC {
    use perpetuals::core::components::positions::Positions as PositionComponent;
    use perpetuals::core::components::positions::positions::Positions::Event as PositionsEvent;
    use starknet::storage::StoragePointerWriteAccess;
    use starkware_utils::components::replaceability::interface::IEICInitializable;


    component!(path: PositionComponent, storage: positions, event: PositionsEvent);


    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        pub positions: PositionComponent::Storage,
        // --- USDC Migration ---
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        PositionsEvent: PositionsEvent,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            self.positions.max_interest_rate_per_sec.write(12000)
        }
    }
}
