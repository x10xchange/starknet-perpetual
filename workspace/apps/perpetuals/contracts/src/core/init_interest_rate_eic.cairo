#[starknet::contract]
mod SetEICInterestRateEIC {
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::positions::Positions;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::replaceability::interface::IEICInitializable;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl,
    };
    use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
    use crate::core::components::positions;


    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(path: Positions, storage: positions, event: PositionsEvent);


    #[storage]
    struct Storage {
        #[substorage(v0)]
        #[allow(starknet::colliding_storage_paths)]
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub positions: Positions::Storage,
        // --- Treasury ---
        treasury: ITreasuryDispatcher,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AssetsEvent: AssetsComponent::Event,
        #[flat]
        PositionsEvent: Positions::Event,
    }


    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            // Maximum interest rate per second (32-bit fixed-point with 32-bit fractional part).
            // Example: max_interest_rate_per_sec = 10 means the rate is 10 / 2^32 ≈ 0.000000232
            // per second, which is approximately 7.4% per year.
            // (1360/2^32) * 60 * 60 * 24 * 365 = 998.586416245% per year
            self.positions.max_interest_rate_per_sec.write(1360);
        }
    }
}
