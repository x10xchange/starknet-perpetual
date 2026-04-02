#[starknet::contract]
mod RegisterTreasuryEIC {
    use starknet::ContractAddress;
    use starknet::storage::StoragePointerWriteAccess;
    use starkware_utils::components::replaceability::interface::IEICInitializable;
    use treasury::interface::ITreasuryDispatcher;

    #[storage]
    struct Storage {
        // --- USDC Migration ---
        treasury: ITreasuryDispatcher,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            assert(eic_init_data.len() == 1, 'EXPECTED_DATA_LENGTH_1');
            let treasury_contract_address: ContractAddress = (*eic_init_data[0])
                .try_into()
                .unwrap();
            let treasury_contract = ITreasuryDispatcher {
                contract_address: treasury_contract_address,
            };
            self.treasury.write(treasury_contract);
        }
    }
}
