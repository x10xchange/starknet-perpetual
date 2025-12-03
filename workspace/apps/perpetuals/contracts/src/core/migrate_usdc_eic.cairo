#[starknet::contract]
mod MigrateTVLEIC {
    use perpetuals::core::core::ITokenMigrationDispatcher;
    use starknet::ContractAddress;
    use starknet::storage::StoragePointerWriteAccess;
    use starkware_utils::components::replaceability::interface::IEICInitializable;

    #[storage]
    struct Storage {
        // --- USDC Migration ---
        migration_contract: ITokenMigrationDispatcher,
    }

    #[abi(embed_v0)]
    impl EICInitializable of IEICInitializable<ContractState> {
        fn eic_initialize(ref self: ContractState, eic_init_data: Span<felt252>) {
            assert(eic_init_data.len() == 1, 'EXPECTED_DATA_LENGTH_1');
            let migration_contract_address: ContractAddress = (*eic_init_data[0])
                .try_into()
                .unwrap();
            let migration_contract = ITokenMigrationDispatcher {
                contract_address: migration_contract_address,
            };

            self.migration_contract.write(migration_contract);
        }
    }
}
