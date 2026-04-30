#[starknet::contract]
mod ReplaceCollateralVaultEIC {
    use openzeppelin::token::erc20::extensions::erc4626::{
        ERC4626Component, ERC4626DefaultNoFees, ERC4626DefaultNoLimits,
    };
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::components::replaceability::interface::IEICInitializable;

    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ERC4626Event: ERC4626Component::Event,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            assert(eic_init_data.len() == 2, 'EXPECTED_DATA_LENGTH_2');
            let usdc_e_contract_address: ContractAddress = (*eic_init_data[0]).try_into().unwrap();
            let usdc_contract_address: ContractAddress = (*eic_init_data[1]).try_into().unwrap();

            let current_contract_address = self.erc4626.ERC4626_asset.read();
            assert!(
                current_contract_address == usdc_e_contract_address,
                "Current collateral address is not USDC E contract address",
            );

            self.erc4626.ERC4626_asset.write(usdc_contract_address);
        }
    }
}
