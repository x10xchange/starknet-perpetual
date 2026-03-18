use perpetuals::core::types::position::PositionId;
use perpetuals::predictions::types::{PredictionSettlement, SignedPredictionOutcome};
use starkware_utils::signature::stark::Signature;
use starkware_utils::time::time::Timestamp;

#[starknet::interface]
pub trait IPredictions<TContractState> {
    fn create_account(ref self: TContractState, client_id: felt252, owning_key: felt252);
    fn deposit_to_prediction_account(
        ref self: TContractState,
        signature: Signature,
        from_position_id: PositionId,
        client_id: felt252,
        quantized_amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn withdraw_from_prediction_account(
        ref self: TContractState,
        signature: Signature,
        to_position_id: PositionId,
        client_id: felt252,
        quantized_amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn create_prediction_market(
        ref self: TContractState,
        market_id: felt252,
        oracle: felt252,
        outcomes: Span<felt252>,
    );
    fn finalize_prediction_market(ref self: TContractState, signed_outcome: SignedPredictionOutcome);
    fn prediction_trade(ref self: TContractState, settlement: PredictionSettlement);
    fn claim(ref self: TContractState, client_id: felt252, market_id: felt252);
}

#[starknet::contract]
pub mod Predictions {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::exchange_time::ExchangeTimeComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::fulfillment::fulfillment::Fulfillement;
    use perpetuals::core::components::fulfillment::interface::IFulfillment;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::types::position::{PositionDiff, PositionId, PositionTrait};
    use perpetuals::predictions::PredictionMarketsComponent;
    use perpetuals::predictions::PredictionPositionsComponent;
    use perpetuals::predictions::prediction_markets::PredictionMarketsComponent::InternalTrait as PredictionMarketsInternal;
    use perpetuals::predictions::prediction_positions::PredictionPositionsComponent::InternalTrait as PredictionPositionsInternal;
    use perpetuals::predictions::predictions::IPredictions;
    use perpetuals::predictions::types::{
        PredictionDepositArgs, PredictionOrder, PredictionSettlement, PredictionWithdrawArgs,
        SignedPredictionOutcome,
    };
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::signature::stark::{Signature, validate_stark_signature};
    use starkware_utils::hash::message_hash::OffchainMessageHash;
    use starkware_utils::time::time::{Time, Timestamp};
    use crate::core::components::external_components::interface::EXTERNAL_COMPONENT_PREDICTIONS;
    use crate::core::components::external_components::named_component::ITypedComponent;
    use crate::core::components::snip::SNIP12MetadataImpl;
    use core::num::traits::Zero;
    use perpetuals::predictions::errors;

    impl SnipImpl = SNIP12MetadataImpl;

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        PositionsEvent: PositionsComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OperatorNonceEvent: OperatorNonceComponent::Event,
        #[flat]
        AssetsEvent: AssetsComponent::Event,
        #[flat]
        RequestApprovalsEvent: RequestApprovalsComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        ExchangeTimeEvent: ExchangeTimeComponent::Event,
        #[flat]
        PredictionPositionsEvent: PredictionPositionsComponent::Event,
        #[flat]
        PredictionMarketsEvent: PredictionMarketsComponent::Event,
        #[flat]
        FulfillmentEvent: Fulfillement::Event,
    }

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub positions: PositionsComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        operator_nonce: OperatorNonceComponent::Storage,
        #[substorage(v0)]
        #[allow(starknet::colliding_storage_paths)]
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        exchange_time: ExchangeTimeComponent::Storage,
        #[substorage(v0)]
        pub prediction_positions: PredictionPositionsComponent::Storage,
        #[substorage(v0)]
        pub prediction_markets: PredictionMarketsComponent::Storage,
        #[substorage(v0)]
        pub fulfillment_tracking: Fulfillement::Storage,
    }

    component!(path: PositionsComponent, storage: positions, event: PositionsEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(
        path: RequestApprovalsComponent, storage: request_approvals, event: RequestApprovalsEvent,
    );
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: ExchangeTimeComponent, storage: exchange_time, event: ExchangeTimeEvent);
    component!(
        path: PredictionPositionsComponent,
        storage: prediction_positions,
        event: PredictionPositionsEvent,
    );
    component!(
        path: PredictionMarketsComponent,
        storage: prediction_markets,
        event: PredictionMarketsEvent,
    );
    component!(path: Fulfillement, storage: fulfillment_tracking, event: FulfillmentEvent);

    #[abi(embed_v0)]
    impl TypedComponent of ITypedComponent<ContractState> {
        fn component_type(ref self: ContractState) -> felt252 {
            EXTERNAL_COMPONENT_PREDICTIONS
        }
    }

    #[abi(embed_v0)]
    impl PredictionsImpl of IPredictions<ContractState> {
        fn create_account(ref self: ContractState, client_id: felt252, owning_key: felt252) {
            self.prediction_positions.create_account(:client_id, :owning_key);
        }

        fn deposit_to_prediction_account(
            ref self: ContractState,
            signature: Signature,
            from_position_id: PositionId,
            client_id: felt252,
            quantized_amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            let deposit_args = PredictionDepositArgs {
                client_id, from_position_id, amount: quantized_amount, expiration, salt,
            };
            let public_key = self
                .positions
                .get_position_snapshot(position_id: from_position_id)
                .get_owner_public_key();
            let hash = self._validate_prediction_signature(:signature, :public_key, :expiration, message: deposit_args);

            let amount_i64: i64 = quantized_amount.try_into().unwrap();
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: from_position_id,
                    :hash,
                    order_base_amount: amount_i64,
                    actual_base_amount: amount_i64,
                );

            let position = self.positions.get_position_mut(position_id: from_position_id);

            // Pull collateral from the perpetuals position.
            let position_diff = PositionDiff {
                collateral_diff: -(quantized_amount.into()), asset_diff: Option::None,
            };

            self
                .positions
                .validate_healthy_or_healthier_position(
                    position_id: from_position_id,
                    position: position.into(),
                    :position_diff,
                    tvtr_before: Default::default(),
                );

            self.positions.apply_diff(position_id: from_position_id, :position_diff);

            self.prediction_positions.deposit_collateral(:client_id, amount: quantized_amount);
        }

        fn withdraw_from_prediction_account(
            ref self: ContractState,
            signature: Signature,
            to_position_id: PositionId,
            client_id: felt252,
            quantized_amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            let withdraw_args = PredictionWithdrawArgs {
                client_id, to_position_id, amount: quantized_amount, expiration, salt,
            };
            let public_key = self.prediction_positions.get_owning_key(:client_id);
            assert(public_key.is_non_zero(), errors::ACCOUNT_DOES_NOT_EXIST);
            let hash = self._validate_prediction_signature(:signature, :public_key, :expiration, message: withdraw_args);

            let amount_i64: i64 = quantized_amount.try_into().unwrap();
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: to_position_id,
                    :hash,
                    order_base_amount: amount_i64,
                    actual_base_amount: amount_i64,
                );

            // Debit the prediction account.
            self.prediction_positions.withdraw_collateral(:client_id, amount: quantized_amount);

            let position_diff = PositionDiff {
                collateral_diff: quantized_amount.into(), asset_diff: Option::None,
            };

            self.positions.apply_diff(position_id: to_position_id, :position_diff);
        }

        fn create_prediction_market(
            ref self: ContractState,
            market_id: felt252,
            oracle: felt252,
            outcomes: Span<felt252>,
        ) {
            self.prediction_markets.create_prediction_market(:market_id, :oracle, :outcomes);
        }

        fn finalize_prediction_market(
            ref self: ContractState, signed_outcome: SignedPredictionOutcome,
        ) {
            let oracle_key = self
                .prediction_markets
                .get_market_oracle(market_id: signed_outcome.market_id);
            assert(oracle_key.is_non_zero(), errors::MARKET_NOT_FOUND);
            PrivateImpl::_validate_oracle_signature(:oracle_key, :signed_outcome);
            self
                .prediction_markets
                .finalize_prediction_market(
                    market_id: signed_outcome.market_id, winner: signed_outcome.outcome,
                );
        }

        fn prediction_trade(ref self: ContractState, settlement: PredictionSettlement) {
            let order_a = settlement.order_a;
            let order_b = settlement.order_b;

            let (hash_a, hash_b) = self._validate_prediction_trade(@settlement);

            // Track fulfillment for partial fills.
            let actual_amount_i64: i64 = settlement.actual_amount.try_into().unwrap();
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: Zero::zero(),
                    hash: hash_a,
                    order_base_amount: order_a.amount,
                    actual_base_amount: actual_amount_i64,
                );
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: Zero::zero(),
                    hash: hash_b,
                    order_base_amount: order_b.amount,
                    actual_base_amount: -actual_amount_i64,
                );

            let actual_amount = settlement.actual_amount;
            let actual_price = settlement.actual_price;
            let market_id = order_a.market_id;
            let outcome = order_a.outcome;

            // Determine buyer and seller.
            let (buyer_id, seller_id) = if order_a.amount > 0 {
                (order_a.client_id, order_b.client_id)
            } else {
                (order_b.client_id, order_a.client_id)
            };

            let (buyer_fee, seller_fee) = if order_a.amount > 0 {
                (settlement.actual_fee_a, settlement.actual_fee_b)
            } else {
                (settlement.actual_fee_b, settlement.actual_fee_a)
            };

            // Mint shares: buyer gets outcome shares, seller gets all other outcome shares.
            self.prediction_positions.add_shares(buyer_id, market_id, outcome, actual_amount);

            let outcomes_count = self.prediction_markets.get_outcomes_count(market_id);
            let mut i: u64 = 0;
            while i < outcomes_count {
                let oc = self.prediction_markets.get_outcome_at(market_id, i);
                if oc != outcome {
                    self.prediction_positions.add_shares(seller_id, market_id, oc, actual_amount);
                }
                i += 1;
            };

            // Buyer pays: actual_amount * actual_price + fee.
            let buyer_cost: u64 = actual_amount * actual_price + buyer_fee;
            self.prediction_positions.withdraw_collateral(client_id: buyer_id, amount: buyer_cost);

            // Seller pays: actual_amount * (PRICE_SCALE - actual_price) + fee.
            // TODO: define PRICE_SCALE constant.
            let seller_cost: u64 = actual_amount * (1000 - actual_price) + seller_fee;
            self
                .prediction_positions
                .withdraw_collateral(client_id: seller_id, amount: seller_cost);

            // Add to pot (excluding fees).
            let pot_amount: u256 = (actual_amount * 1000).into();
            self.prediction_markets.add_to_pot(market_id, amount: pot_amount);

            // Burn complete sets for both users.
            self._burn_complete_sets(buyer_id, market_id);
            self._burn_complete_sets(seller_id, market_id);
        }

        fn claim(ref self: ContractState, client_id: felt252, market_id: felt252) {
            assert(
                self.prediction_markets.is_market_finalized(market_id),
                errors::MARKET_NOT_FINALIZED,
            );
            let winner = self.prediction_markets.get_market_winner(market_id);
            let shares = self.prediction_positions.get_position(client_id, market_id, winner);
            assert(shares > 0, errors::INVALID_ZERO_AMOUNT);

            // Zero out winning shares.
            self.prediction_positions.sub_shares(client_id, market_id, winner, shares);

            // Return collateral from pot.
            // TODO: use PRICE_SCALE instead of 1000.
            let payout: u64 = shares * 1000;
            let payout_u256: u256 = payout.into();
            self.prediction_markets.sub_from_pot(market_id, amount: payout_u256);
            self.prediction_positions.deposit_collateral(client_id, amount: payout);
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _validate_prediction_signature<T, +Drop<T>, +Copy<T>, +OffchainMessageHash<T>>(
            self: @ContractState,
            signature: Signature,
            public_key: felt252,
            expiration: Timestamp,
            message: T,
        ) -> felt252 {
            assert(Time::now() <= expiration, errors::SIGNATURE_EXPIRED);
            let msg_hash = message.get_message_hash(:public_key);
            validate_stark_signature(:public_key, :msg_hash, :signature);
            msg_hash
        }

        fn _validate_prediction_trade(
            self: @ContractState, settlement: @PredictionSettlement,
        ) -> (felt252, felt252) {
            let order_a = *settlement.order_a;
            let order_b = *settlement.order_b;
            let actual_amount = *settlement.actual_amount;
            let actual_price = *settlement.actual_price;

            // Same market and outcome.
            assert(order_a.market_id == order_b.market_id, errors::MISMATCHED_MARKETS);
            assert(order_a.outcome == order_b.outcome, errors::MISMATCHED_OUTCOMES);

            // Market exists and is not finalized.
            let oracle = self.prediction_markets.get_market_oracle(market_id: order_a.market_id);
            assert(oracle.is_non_zero(), errors::MARKET_NOT_FOUND);
            assert(
                !self.prediction_markets.is_market_finalized(market_id: order_a.market_id),
                errors::MARKET_ALREADY_FINALIZED,
            );

            // Valid outcome.
            self.prediction_markets.assert_valid_outcome(
                market_id: order_a.market_id, outcome_id: order_a.outcome,
            );

            // Non-zero actual amount.
            assert(actual_amount.is_non_zero(), errors::INVALID_ZERO_AMOUNT);

            // Amounts must have opposite signs (one buyer, one seller).
            assert(
                (order_a.amount > 0 && order_b.amount < 0)
                    || (order_a.amount < 0 && order_b.amount > 0),
                errors::INVALID_AMOUNT_SIGN,
            );

            // Price protection.
            // Buyer (amount > 0): actual_price <= order.price.
            // Seller (amount < 0): actual_price >= order.price.
            if order_a.amount > 0 {
                assert(actual_price <= order_a.price, errors::INVALID_BUYER_PRICE);
                assert(actual_price >= order_b.price, errors::INVALID_SELLER_PRICE);
            } else {
                assert(actual_price >= order_a.price, errors::INVALID_SELLER_PRICE);
                assert(actual_price <= order_b.price, errors::INVALID_BUYER_PRICE);
            }

            // Fee caps.
            assert(*settlement.actual_fee_a <= order_a.fee_amount, errors::INVALID_FEE);
            assert(*settlement.actual_fee_b <= order_b.fee_amount, errors::INVALID_FEE);

            // Validate signatures.
            let public_key_a = self
                .prediction_positions
                .get_owning_key(client_id: order_a.client_id);
            assert(public_key_a.is_non_zero(), errors::ACCOUNT_DOES_NOT_EXIST);
            let hash_a = self._validate_prediction_signature(
                signature: *settlement.signature_a,
                public_key: public_key_a,
                expiration: order_a.expiration,
                message: order_a,
            );

            let public_key_b = self
                .prediction_positions
                .get_owning_key(client_id: order_b.client_id);
            assert(public_key_b.is_non_zero(), errors::ACCOUNT_DOES_NOT_EXIST);
            let hash_b = self._validate_prediction_signature(
                signature: *settlement.signature_b,
                public_key: public_key_b,
                expiration: order_b.expiration,
                message: order_b,
            );

            (hash_a, hash_b)
        }

        fn _burn_complete_sets(
            ref self: ContractState, client_id: felt252, market_id: felt252,
        ) {
            let outcomes_count = self.prediction_markets.get_outcomes_count(market_id);

            // Find minimum across all outcomes.
            let mut min_shares: u64 = core::num::traits::Bounded::<u64>::MAX;
            let mut i: u64 = 0;
            while i < outcomes_count {
                let oc = self.prediction_markets.get_outcome_at(market_id, i);
                let shares = self.prediction_positions.get_position(client_id, market_id, oc);
                if shares == 0 {
                    return;
                }
                if shares < min_shares {
                    min_shares = shares;
                }
                i += 1;
            };

            // Burn min_shares from each outcome.
            let mut j: u64 = 0;
            while j < outcomes_count {
                let oc = self.prediction_markets.get_outcome_at(market_id, j);
                self.prediction_positions.sub_shares(client_id, market_id, oc, min_shares);
                j += 1;
            };

            // Return collateral from pot.
            // TODO: use PRICE_SCALE instead of 1000.
            let refund: u64 = min_shares * 1000;
            let refund_u256: u256 = refund.into();
            self.prediction_markets.sub_from_pot(market_id, amount: refund_u256);
            self.prediction_positions.deposit_collateral(client_id, amount: refund);
        }

        fn _validate_oracle_signature(
            oracle_key: felt252, signed_outcome: SignedPredictionOutcome,
        ) {
            let msg_hash = core::pedersen::pedersen(
                core::pedersen::pedersen(signed_outcome.market_id, signed_outcome.outcome),
                signed_outcome.timestamp.into(),
            );
            validate_stark_signature(
                public_key: oracle_key, :msg_hash, signature: signed_outcome.signature,
            );
        }
    }
}
