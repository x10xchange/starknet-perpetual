#[starknet::contract]
mod FixAssetManagerEIC {
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::core::{ITokenMigrationDispatcher, ITokenMigrationDispatcherTrait};
    use starknet::get_contract_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::components::replaceability::interface::IEICInitializable;

    use starkware_utils::time::time::{Time, TimeDelta, Timestamp};


    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);


    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        pub assets: AssetsComponent::Storage,
        // --- USDC Migration ---
        migration_contract: ITokenMigrationDispatcher,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AssetsEvent: AssetsComponent::Event,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            self.assets.max_oracle_price_validity.write(TimeDelta { seconds: 7 * 24 * 3600 });
            self.assets.max_price_interval.write(TimeDelta { seconds: 7 * 24 * 3600 });
            self.assets.max_funding_interval.write(TimeDelta { seconds: 7 * 24 * 3600 });
        }
    }
}
