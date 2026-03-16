use perpetuals::core::types::position::PositionId;
use perpetuals::predictions::types::{PredictionDepositArgs, PredictionWithdrawArgs};
use starknet::ContractAddress;
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
    use perpetuals::core::types::position::{PositionDiff, PositionId};
    use perpetuals::predictions::PredictionPositionsComponent;
    use perpetuals::predictions::prediction_positions::PredictionPositionsComponent::InternalTrait as PredictionPositionsInternal;
    use perpetuals::predictions::predictions::IPredictions;
    use perpetuals::predictions::types::{PredictionDepositArgs, PredictionWithdrawArgs};
    use starknet::ContractAddress;
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::signature::stark::{Signature, validate_stark_signature};
    use starkware_utils::hash::message_hash::OffchainMessageHash;
    use starkware_utils::time::time::{Time, Timestamp};
    use crate::core::components::external_components::interface::EXTERNAL_COMPONENT_PREDICTIONS;
    use crate::core::components::external_components::named_component::ITypedComponent;
    use crate::core::components::snip::SNIP12MetadataImpl;

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
                client_id, amount: quantized_amount, expiration, salt,
            };
            let hash = self._validate_prediction_signature(:signature, :client_id, :expiration, message: deposit_args);

            let amount_felt: felt252 = quantized_amount.into();
            let amount_i64: i64 = amount_felt.try_into().unwrap();
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

            let amount = quantized_amount;
            self.prediction_positions.deposit_collateral(:client_id, :amount);
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
                client_id, amount: quantized_amount, expiration, salt,
            };
            let hash = self._validate_prediction_signature(:signature, :client_id, :expiration, message: withdraw_args);

            let amount_felt: felt252 = quantized_amount.into();
            let amount_i64: i64 = amount_felt.try_into().unwrap();
            self
                .fulfillment_tracking
                .update_fulfillment(
                    position_id: to_position_id,
                    :hash,
                    order_base_amount: amount_i64,
                    actual_base_amount: amount_i64,
                );

            let amount = quantized_amount;
            // Debit the prediction account.
            self.prediction_positions.withdraw_collateral(:client_id, :amount);

            let position_diff = PositionDiff {
                collateral_diff: quantized_amount.into(), asset_diff: Option::None,
            };

            self.positions.apply_diff(position_id: to_position_id, :position_diff);
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _validate_prediction_signature<T, +Drop<T>, +Copy<T>, +OffchainMessageHash<T>>(
            self: @ContractState,
            signature: Signature,
            client_id: felt252,
            expiration: Timestamp,
            message: T,
        ) -> felt252 {
            assert!(Time::now() <= expiration, "SIGNATURE_EXPIRED");
            let public_key = self.prediction_positions.get_owning_key(:client_id);
            let msg_hash = message.get_message_hash(:public_key);
            validate_stark_signature(:public_key, :msg_hash, :signature);
            msg_hash
        }
    }
}
