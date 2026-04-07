#[starknet::contract]
mod MigrateCollateralToTreasuryEIC {
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::replaceability::interface::IEICInitializable;
    use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};

    #[storage]
    struct Storage {
        // --- Treasury ---
        treasury: ITreasuryDispatcher,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        /// Registers the treasury and migrates all collateral balances from the perps contract
        /// into it.
        /// eic_init_data: [treasury_address, collateral_address_0, collateral_address_1, ...]
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            assert(eic_init_data.len() >= 1, 'EXPECTED_AT_LEAST_1_ELEMENT');

            // Register the treasury.
            let treasury_contract_address: ContractAddress = (*eic_init_data[0])
                .try_into()
                .unwrap();
            let treasury = ITreasuryDispatcher {
                contract_address: treasury_contract_address,
            };
            self.treasury.write(treasury);

            // Migrate collateral balances to the treasury.
            let perps_address = get_contract_address();
            let mut i: u32 = 1;
            while i < eic_init_data.len() {
                let collateral_address: ContractAddress = (*eic_init_data[i])
                    .try_into()
                    .unwrap();
                let collateral = IERC20Dispatcher { contract_address: collateral_address };
                let balance = collateral.balance_of(perps_address);
                if balance > 0 {
                    assert(collateral.approve(treasury_contract_address, balance), 'APPROVE_FAILED');
                    treasury.deposit_into(collateral_address, balance);
                }
                i += 1;
            };
        }
    }
}
