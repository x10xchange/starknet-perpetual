#[starknet::component]
pub mod PredictionMarketsComponent {
    use core::num::traits::Zero;
    use perpetuals::predictions::errors;
    use perpetuals::predictions::prediction_positions::PredictionPositionsComponent;
    use perpetuals::predictions::types::Market;
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess, VecTrait,
    };

    #[storage]
    pub struct Storage {
        pub markets: Map<felt252, Market>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {

    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Positions: PredictionPositionsComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn create_prediction_market(
            ref self: ComponentState<TContractState>,
            market_id: felt252,
            oracle: felt252,
            outcomes: Span<felt252>,
        ) {
            let market = self.markets.entry(market_id);
            assert(market.oracle.read().is_zero(), errors::MARKET_ALREADY_EXISTS);
            assert(oracle.is_non_zero(), errors::INVALID_ZERO_ORACLE);
            assert(outcomes.len() >= 2, errors::INSUFFICIENT_OUTCOMES);
            market.oracle.write(oracle);
            for outcome in outcomes {
                market.outcomes.push(*outcome);
            };
        }

        fn finalize_prediction_market(
            ref self: ComponentState<TContractState>,
            market_id: felt252,
            winner: felt252,
        ) {
            let market = self.markets.entry(market_id);
            assert(market.oracle.read().is_non_zero(), errors::MARKET_NOT_FOUND);
            assert(!market.is_finalized.read(), errors::MARKET_ALREADY_FINALIZED);
            self.assert_valid_outcome(:market_id, outcome_id: winner);
            market.winner.write(winner);
            market.is_finalized.write(true);
        }

        fn get_market_oracle(
            self: @ComponentState<TContractState>, market_id: felt252,
        ) -> felt252 {
            self.markets.entry(market_id).oracle.read()
        }

        fn assert_valid_outcome(
            self: @ComponentState<TContractState>, market_id: felt252, outcome_id: felt252,
        ) {
            let market = self.markets.entry(market_id);
            let len = market.outcomes.len();
            let mut found = false;
            let mut i: u64 = 0;
            while i < len {
                if market.outcomes.at(i).read() == outcome_id {
                    found = true;
                    break;
                }
                i += 1;
            };
            assert(found, errors::INVALID_OUTCOME);
        }
    }
}
