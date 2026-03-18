#[starknet::interface]
pub trait IPredictionPositions<TContractState> {
    fn get_prediction_collateral(self: @TContractState, client_id: felt252) -> u64;
    fn get_prediction_position(
        self: @TContractState, client_id: felt252, market_id: felt252, outcome_id: felt252,
    ) -> u64;
}

#[starknet::component]
pub mod PredictionPositionsComponent {
    use core::num::traits::Zero;
    use perpetuals::predictions::errors;
    use perpetuals::predictions::types::Account;
    use starknet::storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    pub struct Storage {
        pub accounts: Map<felt252, Account>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(PredictionPositionsImpl)]
    impl PredictionPositionsExternal<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of super::IPredictionPositions<ComponentState<TContractState>> {
        fn get_prediction_collateral(
            self: @ComponentState<TContractState>, client_id: felt252,
        ) -> u64 {
            self.accounts.entry(client_id).collateral.read()
        }

        fn get_prediction_position(
            self: @ComponentState<TContractState>,
            client_id: felt252,
            market_id: felt252,
            outcome_id: felt252,
        ) -> u64 {
            self.accounts.entry(client_id).positions.entry(market_id).entry(outcome_id).read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn create_account(
            ref self: ComponentState<TContractState>,
            client_id: felt252,
            owning_key: felt252,
        ) {
            let account = self.accounts.entry(client_id);
            assert(account.owning_key.read().is_zero(), errors::ACCOUNT_ALREADY_EXISTS);
            assert(owning_key.is_non_zero(), errors::INVALID_ZERO_OWNING_KEY);
            account.owning_key.write(owning_key);
        }

        fn deposit_collateral(
            ref self: ComponentState<TContractState>,
            client_id: felt252,
            amount: u64,
        ) {
            let account = self.accounts.entry(client_id);
            assert(account.owning_key.read().is_non_zero(), errors::ACCOUNT_DOES_NOT_EXIST);
            let current_collateral = account.collateral.read();
            account.collateral.write(current_collateral + amount);
        }

        fn withdraw_collateral(
            ref self: ComponentState<TContractState>,
            client_id: felt252,
            amount: u64,
        ) {
            let account = self.accounts.entry(client_id);
            assert(account.owning_key.read().is_non_zero(), errors::ACCOUNT_DOES_NOT_EXIST);
            let current_collateral = account.collateral.read();
            assert(current_collateral >= amount, errors::INSUFFICIENT_COLLATERAL);
            account.collateral.write(current_collateral - amount);
        }

        fn get_collateral(
            self: @ComponentState<TContractState>, client_id: felt252,
        ) -> u64 {
            self.accounts.entry(client_id).collateral.read()
        }

        fn get_owning_key(
            self: @ComponentState<TContractState>, client_id: felt252,
        ) -> felt252 {
            self.accounts.entry(client_id).owning_key.read()
        }

        fn set_owning_key(
            ref self: ComponentState<TContractState>,
            client_id: felt252,
            owning_key: felt252,
        ) {
            self.accounts.entry(client_id).owning_key.write(owning_key);
        }

        fn get_position(
            self: @ComponentState<TContractState>,
            client_id: felt252,
            market_id: felt252,
            outcome_id: felt252,
        ) -> u64 {
            self.accounts.entry(client_id).positions.entry(market_id).entry(outcome_id).read()
        }

        fn add_shares(
            ref self: ComponentState<TContractState>,
            client_id: felt252,
            market_id: felt252,
            outcome_id: felt252,
            amount: u64,
        ) {
            let pos = self.accounts.entry(client_id).positions.entry(market_id).entry(outcome_id);
            pos.write(pos.read() + amount);
        }

        fn sub_shares(
            ref self: ComponentState<TContractState>,
            client_id: felt252,
            market_id: felt252,
            outcome_id: felt252,
            amount: u64,
        ) {
            let pos = self.accounts.entry(client_id).positions.entry(market_id).entry(outcome_id);
            pos.write(pos.read() - amount);
        }
    }
}
