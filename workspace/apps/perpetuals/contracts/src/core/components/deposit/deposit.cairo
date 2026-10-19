#[starknet::component]
pub(crate) mod Deposit {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::deposit::errors;
    use perpetuals::core::components::deposit::interface::{DepositStatus, IDeposit};
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::position::PositionId;
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::signature::stark::HashType;
    use starkware_utils::time::time::{Time, TimeDelta};
    use crate::core::components::assets::interface::IAssets;
    use crate::core::components::deposit::deposit_manager::IDepositExternalDispatcherTrait;
    use crate::core::components::external_components::external_component_manager::ExternalComponents as ExternalComponentsComponent;
    use crate::core::components::external_components::external_component_manager::ExternalComponents::InternalTrait as ExternalComponentsInternalTrait;
    use crate::core::components::vaults::vaults::Vaults as VaultsComponent;
    use super::super::events;


    #[storage]
    pub struct Storage {
        pub registered_deposits: Map<HashType, DepositStatus>,
        pub cancel_delay: TimeDelta,
        pub bridge_operator: ContractAddress,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        DepositBridgeOperatorUpdated: events::DepositBridgeOperatorUpdated,
        FundsBridged: events::FundsBridged,
    }


    #[embeddable_as(DepositImpl)]
    impl Deposit<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
        impl Vaults: VaultsComponent::HasComponent<TContractState>,
        impl ExternalComponents: ExternalComponentsComponent::HasComponent<TContractState>,
    > of IDeposit<ComponentState<TContractState>> {
        fn deposit(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            let assets = get_dep_component!(@self, Assets);
            let pnl_collateral_id = assets.get_base_collateral_id();
            self.deposit_asset(asset_id: pnl_collateral_id, :position_id, :quantized_amount, :salt)
        }

        /// Accept base collateral into Core and emit Deposit for off-chain bridging.
        /// No pending deposit record is created and no Starknet position is credited.
        fn deposit_asset(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            assert(quantized_amount.is_non_zero(), errors::ZERO_AMOUNT);
            let caller_address = get_caller_address();
            let external_components = get_dep_component!(@self, ExternalComponents);
            external_components
                ._get_deposit_manager_dispatcher()
                .deposit(
                    caller_address: caller_address,
                    asset_id: asset_id,
                    position_id: position_id,
                    quantized_amount: quantized_amount,
                    now: Time::now(),
                    salt: salt,
                );
        }

        /// Disabled by the post-migration DepositManager.
        fn cancel_deposit(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            let depositor = get_caller_address();
            let external_components = get_dep_component!(@self, ExternalComponents);
            external_components
                ._get_deposit_manager_dispatcher()
                .cancel_deposit(
                    depositor: depositor,
                    asset_id: asset_id,
                    position_id: position_id,
                    quantized_amount: quantized_amount,
                    now: Time::now(),
                    salt: salt,
                );
        }


        /// Disabled by the post-migration DepositManager.
        fn reject_deposit(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            depositor: ContractAddress,
            asset_id: AssetId,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
        ) {
            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);
            let external_components = get_dep_component!(@self, ExternalComponents);
            external_components
                ._get_deposit_manager_dispatcher()
                .reject_deposit(
                    depositor: depositor,
                    asset_id: asset_id,
                    position_id: position_id,
                    quantized_amount: quantized_amount,
                    now: Time::now(),
                    salt: salt,
                );
        }


        /// Disabled by the post-migration DepositManager.
        fn process_deposit(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            depositor: ContractAddress,
            asset_id: AssetId,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252,
            interest_amount: i64,
        ) {
            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(:operator_nonce);
            let external_components = get_dep_component!(@self, ExternalComponents);
            external_components
                ._get_deposit_manager_dispatcher()
                .process_deposit(
                    depositor: depositor,
                    asset_id: asset_id,
                    position_id: position_id,
                    quantized_amount: quantized_amount,
                    salt: salt,
                    interest_amount: interest_amount,
                );
        }

        fn set_deposit_bridge_operator(
            ref self: ComponentState<TContractState>, operator: ContractAddress,
        ) {
            get_dep_component!(@self, Roles).only_app_governor();
            assert(operator.is_non_zero(), 'INVALID_BRIDGE_OPERATOR');
            self.bridge_operator.write(operator);
            self.emit(events::DepositBridgeOperatorUpdated { operator });
        }

        fn get_deposit_bridge_operator(self: @ComponentState<TContractState>) -> ContractAddress {
            self.bridge_operator.read()
        }

        fn bridge_funds(
            ref self: ComponentState<TContractState>, amount: u256, commitment_id: felt252,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            let external_components = get_dep_component!(@self, ExternalComponents);
            external_components
                ._get_deposit_manager_dispatcher()
                .bridge_funds(amount, commitment_id);
        }

        fn get_deposit_status(
            self: @ComponentState<TContractState>, deposit_hash: HashType,
        ) -> DepositStatus {
            self.registered_deposits.read(deposit_hash)
        }

        fn get_cancel_delay(self: @ComponentState<TContractState>) -> TimeDelta {
            self.cancel_delay.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
        impl Vaults: VaultsComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, cancel_delay: TimeDelta) {
            assert(self.cancel_delay.read().is_zero(), errors::ALREADY_INITIALIZED);
            assert(cancel_delay.is_non_zero(), errors::INVALID_CANCEL_DELAY);
            self.cancel_delay.write(cancel_delay);
        }
    }
}
