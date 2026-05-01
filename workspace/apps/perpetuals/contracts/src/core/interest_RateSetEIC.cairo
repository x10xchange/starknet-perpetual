#[starknet::contract]
mod SetEICInterestRateEIC {
    use crate::core::components::positions;
use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use perpetuals::core::components::assets::AssetsComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::replaceability::interface::IEICInitializable;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl,
    };
    use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
    use perpetuals::core::components::positions::Positions;


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
        /// Registers the treasury and migrates all collateral balances from the perps contract
        /// into it.
        /// eic_init_data: [treasury_address]
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            self.positions.max_interest_rate_per_sec.write(12000);
        }
    }
}
