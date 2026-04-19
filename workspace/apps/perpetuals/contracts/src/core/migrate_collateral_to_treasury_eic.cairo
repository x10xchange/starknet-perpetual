#[starknet::contract]
mod MigrateCollateralToTreasuryEIC {
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use perpetuals::core::components::assets::AssetsComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::replaceability::interface::IEICInitializable;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl,
    };
    use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};

    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        #[allow(starknet::colliding_storage_paths)]
        pub assets: AssetsComponent::Storage,
        // --- Treasury ---
        treasury: ITreasuryDispatcher,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AssetsEvent: AssetsComponent::Event,
    }

    fn migrate_token(
        token_address: ContractAddress,
        perps_address: ContractAddress,
        treasury_address: ContractAddress,
        ref treasury: ITreasuryDispatcher,
    ) {
        let token = IERC20Dispatcher { contract_address: token_address };
        let balance = token.balance_of(perps_address);
        if balance > 0 {
            assert(token.approve(treasury_address, balance), 'APPROVE_FAILED');
            treasury.deposit_into(token_address, balance);
        }
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        /// Registers the treasury and migrates all collateral balances from the perps contract
        /// into it.
        /// eic_init_data: [treasury_address]
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            assert(eic_init_data.len() == 1, 'EXPECTED_1_ELEMENT');
            let perps_address = get_contract_address();

            // Register the treasury.
            let treasury_contract_address: ContractAddress = (*eic_init_data[0])
                .try_into()
                .unwrap();
            let mut treasury = ITreasuryDispatcher { contract_address: treasury_contract_address };
            assert(treasury.get_perps_contract() == perps_address, 'TREASURY_PERPS_MISMATCH');
            self.treasury.write(treasury);

            // Migrate base collateral.
            let base_collateral = self.assets.collateral_token_contract.read();
            migrate_token(
                base_collateral.contract_address,
                perps_address,
                treasury_contract_address,
                ref treasury,
            );

            // Migrate all registered assets (vault shares, etc.) by iterating the asset map.
            for (asset_id, _) in self.assets.timely_data {
                let config = match self.assets.asset_config.read(asset_id) {
                    Option::Some(c) => c,
                    Option::None => { continue; },
                };
                let token_address = match config.token_contract {
                    Option::Some(addr) => addr,
                    Option::None => { continue; },
                };
                migrate_token(
                    token_address, perps_address, treasury_contract_address, ref treasury,
                );
            };
        }
    }
}
