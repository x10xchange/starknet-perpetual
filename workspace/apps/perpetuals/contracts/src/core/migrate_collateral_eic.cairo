#[starknet::contract]
mod ReplaceCollateralEIC {
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::core::{ITokenMigrationDispatcher, ITokenMigrationDispatcherTrait};
    use starknet::get_contract_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::components::replaceability::interface::IEICInitializable;


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
            let perps_address = get_contract_address();
            let migration_contract = self.migration_contract.read();

            let usdc_e_contract_address = migration_contract.get_legacy_token();
            let usdc_e = IERC20Dispatcher { contract_address: usdc_e_contract_address };
            let usdc = IERC20Dispatcher { contract_address: migration_contract.get_new_token() };

            let usdc_e_balance = usdc_e.balance_of(account: perps_address);
            let usdc_balance = usdc.balance_of(account: perps_address);

            assert!(
                2 * usdc_balance >= usdc_e_balance,
                "replace collateral address must be only after 1/3 already migrated",
            )

            let current_contract_address = self
                .assets
                .collateral_token_contract
                .contract_address
                .read();
            assert!(
                current_contract_address == usdc_e_contract_address,
                "Current collateral address is not USDC E contract address",
            );
            self.assets.collateral_token_contract.write(usdc);
        }
    }
}
