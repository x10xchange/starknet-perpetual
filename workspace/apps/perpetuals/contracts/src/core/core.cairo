#[starknet::contract]
pub mod Core {
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::replaceability::ReplaceabilityComponent;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
    use contracts_commons::types::time::{Time, TimeDelta, Timestamp};
    use core::num::traits::Zero;
    use core::starknet::storage::StoragePointerWriteAccess;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin::account::utils::is_valid_stark_signature;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::utils::cryptography::nonces::NoncesComponent;
    use openzeppelin::utils::snip12::SNIP12Metadata;
    use perpetuals::core::errors::*;
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::collateral::{
        CollateralAsset, CollateralConfig, CollateralTimelyData,
    };
    use perpetuals::core::types::asset::synthetic::{
        SyntheticAsset, SyntheticConfig, SyntheticTimelyData,
    };
    use perpetuals::core::types::node::Node;
    use perpetuals::core::types::{PositionData, Signature};
    use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
    use starknet::storage::{Map, StoragePathEntry, Vec};
    use starknet::{ContractAddress, get_contract_address};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesComponentInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    const NAME: felt252 = 'Perpetuals';
    const VERSION: felt252 = 'v0';

    /// Required for hash computation.
    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            NAME
        }
        fn version() -> felt252 {
            VERSION
        }
    }

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // --- Initialization ---
        value_risk_calculator_dispatcher: IValueRiskCalculatorDispatcher,
        contract_address: ContractAddress,
        // --- System Configuration ---
        price_validation_interval: TimeDelta,
        funding_validation_interval: TimeDelta,
        max_funding_rate: FixedTwoDecimal,
        // --- Validations ---
        // Updates each price validation.
        last_price_validation: Timestamp,
        // Updates every funding tick.
        last_funding_tick: Timestamp,
        // Message hash to fulfilled amount.
        fulfillment: Map<felt252, i128>,
        // --- Asset Configuration ---
        collateral_configs: Map<AssetId, Option<CollateralConfig>>,
        synthetic_configs: Map<AssetId, Option<SyntheticConfig>>,
        oracles: Map<AssetId, Vec<ContractAddress>>,
        // --- Asset Data ---
        collateral_timely_data: Map<AssetId, CollateralTimelyData>,
        synthetic_timely_data: Map<AssetId, SyntheticTimelyData>,
        // --- Position Data ---
        positions: Map<felt252, Position>,
    }

    #[starknet::storage_node]
    struct Position {
        version: u8,
        owner_account: ContractAddress,
        owner_public_key: felt252,
        collateral_assets: Map<AssetId, CollateralAsset>,
        synthetic_assets: Map<AssetId, SyntheticAsset>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    pub fn constructor(ref self: ContractState, value_risk_calculator: ContractAddress) {
        self
            .value_risk_calculator_dispatcher
            .write(IValueRiskCalculatorDispatcher { contract_address: value_risk_calculator });
        self.contract_address.write(get_contract_address());
    }

    #[abi(embed_v0)]
    pub impl CoreImpl of ICore<ContractState> {
        // Flows
        fn deleverage(self: @ContractState) {}
        fn deposit(self: @ContractState) {}
        fn liquidate(self: @ContractState) {}
        fn trade(self: @ContractState) {}
        fn transfer(self: @ContractState) {}
        fn withdraw(
            ref self: ContractState,
            position_id: felt252,
            collateral_id: AssetId,
            recipient: ContractAddress,
            nonce: felt252,
            expiry: Timestamp,
            amount: u128,
            salt: felt252,
            signature: Signature,
        ) {}

        // Funding
        fn funding_tick(self: @ContractState) {}

        // Configuration
        fn add_asset(self: @ContractState) {}
        fn add_oracle(self: @ContractState) {}
        fn add_oracle_to_asset(self: @ContractState) {}
        fn remove_oracle(self: @ContractState) {}
        fn remove_oracle_from_asset(self: @ContractState) {}
        fn update_asset_price(self: @ContractState) {}
        fn update_max_funding_rate(self: @ContractState) {}
        fn update_oracle_identifiers(self: @ContractState) {}
    }

    #[generate_trait]
    pub impl InternalCoreFunctions of InternalCoreFunctionsTrait {
        fn _apply_funding(self: @ContractState) {}
        fn _get_asset_price(self: @ContractState) {}
        fn _pre_update(self: @ContractState) {}
        fn _post_update(self: @ContractState) {}

        /// If `price_validation_interval` has passed since `last_price_validation`, validate
        /// synthetic and collateral prices and update `last_price_validation` to current time.
        fn _validate_prices(ref self: ContractState) {
            let now = Time::now();
            let price_validation_interval = self.price_validation_interval.read();
            if now.sub(self.last_price_validation.read()) >= price_validation_interval {
                self._validate_synthetic_prices(now, price_validation_interval);
                self._validate_collateral_prices(now, price_validation_interval);
                self.last_price_validation.write(now);
            }
        }

        fn _validate_synthetic_prices(
            self: @ContractState, now: Timestamp, price_validation_interval: TimeDelta,
        ) {
            let mut head: SyntheticTimelyData = Node::head();
            while head.next.is_some() {
                let last_price_update = self
                    .synthetic_timely_data
                    .read(head.next.unwrap())
                    .last_price_update;
                assert(now.sub(last_price_update) < price_validation_interval, EXPIRED_PRICE);
                head = self.synthetic_timely_data.read(head.next.unwrap());
            };
        }


        fn _validate_collateral_prices(
            self: @ContractState, now: Timestamp, price_validation_interval: TimeDelta,
        ) {
            let mut head: CollateralTimelyData = Node::head();
            while head.next.is_some() {
                let last_price_update = self
                    .synthetic_timely_data
                    .read(head.next.unwrap())
                    .last_price_update;
                assert(now.sub(last_price_update) < price_validation_interval, EXPIRED_PRICE);
                head = self.collateral_timely_data.read(head.next.unwrap());
            };
        }

        fn _validate_stark_signature(
            self: @ContractState, public_key: felt252, hash: felt252, signature: Signature,
        ) {
            assert(
                is_valid_stark_signature(msg_hash: hash, :public_key, signature: signature.span()),
                INVALID_STARK_SIGNATURE,
            );
        }

        fn _validate_owner_signature(
            self: @ContractState, owner: ContractAddress, hash: felt252, signature: Signature,
        ) {
            let is_valid_signature_felt = ISRC6Dispatcher { contract_address: owner }
                .is_valid_signature(hash, signature);
            // Check either 'VALID' or true for backwards compatibility.
            let signature_valid = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;
            assert(signature_valid, INVALID_OWNER_SIGNATURE);
        }

        fn _get_position_data(self: @ContractState, position_id: felt252) -> PositionData {
            let position = self.positions.entry(position_id);
            assert(position.owner_account.read().is_non_zero(), INVALID_POSITION);
            // TODO: Implement the 'asset_entries' field.
            PositionData { version: position.version.read(), asset_entries: array![].span() }
        }

        fn _get_collateral_config(
            self: @ContractState, collateral_id: AssetId,
        ) -> CollateralConfig {
            self.collateral_configs.read(collateral_id).expect(COLLATERAL_NOT_EXISTS)
        }

        fn _get_synthetic_config(self: @ContractState, synthetic_id: AssetId) -> SyntheticConfig {
            self.synthetic_configs.read(synthetic_id).expect(SYNTHETIC_NOT_EXISTS)
        }
    }
}
