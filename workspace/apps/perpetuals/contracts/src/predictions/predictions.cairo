use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IPredictions<TContractState> {
    fn create_account(ref self: TContractState, client_id: felt252, owning_key: felt252);
    fn deposit_to_prediction_account(
        ref self: TContractState,
        from_position_id: PositionId,
        client_id: felt252,
        quantized_amount: u64,
        caller_address: ContractAddress,
    );
    fn withdraw_from_prediction_account(
        ref self: TContractState,
        to_position_id: PositionId,
        client_id: felt252,
        quantized_amount: u64,
        caller_address: ContractAddress,
    );
}

#[starknet::contract]
pub mod Predictions {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::exchange_time::ExchangeTimeComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::types::position::{PositionDiff, PositionId};
    use perpetuals::predictions::PredictionPositionsComponent;
    use perpetuals::predictions::prediction_positions::PredictionPositionsComponent::InternalTrait as PredictionPositionsInternal;
    use perpetuals::predictions::predictions::IPredictions;
    use starknet::ContractAddress;
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;

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

    #[abi(embed_v0)]
    impl PredictionsImpl of IPredictions<ContractState> {
        fn create_account(ref self: ContractState, client_id: felt252, owning_key: felt252) {
            self.prediction_positions.create_account(:client_id, :owning_key);
        }

        fn deposit_to_prediction_account(
            ref self: ContractState,
            from_position_id: PositionId,
            client_id: felt252,
            quantized_amount: u64,
            caller_address: ContractAddress,
        ) {
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
            to_position_id: PositionId,
            client_id: felt252,
            quantized_amount: u64,
            caller_address: ContractAddress,
        ) {
            let amount = quantized_amount;
            // Debit the prediction account.
            self.prediction_positions.withdraw_collateral(:client_id, :amount);

            let position_diff = PositionDiff {
                collateral_diff: quantized_amount.into(), asset_diff: Option::None,
            };

            self.positions.apply_diff(position_id: to_position_id, :position_diff);
        }
    }
}
