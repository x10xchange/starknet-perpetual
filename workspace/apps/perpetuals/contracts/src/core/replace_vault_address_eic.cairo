#[starknet::contract]
mod ReplaceCollateralEIC {
    use core::num::traits::Zero;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::types::asset::AssetId;
    use starknet::storage::{StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::replaceability::interface::IEICInitializable;

    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        pub assets: AssetsComponent::Storage,
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
            assert(eic_init_data.len() == 3, 'EXPECTED_DATA_LENGTH_3');

            let asset_id: AssetId = (*eic_init_data[0]).try_into().unwrap();
            let new_token_contract: ContractAddress = (*eic_init_data[1]).try_into().unwrap();
            let old_token_contract: ContractAddress = (*eic_init_data[2]).try_into().unwrap();

            // Replace vault token address.
            let asset_config_opt = self.assets.asset_config.entry(asset_id).read();
            let mut asset_config = asset_config_opt.expect('ASSET_CONFIG_NOT_EXIST');
            assert(asset_config.token_contract == Some(old_token_contract), 'ILLEGAL_OLD_TOKEN');
            asset_config.token_contract = Some(new_token_contract);
            self.assets.asset_config.entry(asset_id).write(Some(asset_config));
        }
    }
}
