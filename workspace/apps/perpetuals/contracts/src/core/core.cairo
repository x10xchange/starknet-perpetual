#[starknet::contract]
pub mod Core {
    use contracts_commons::types::time::TimeStamp;
    use core::starknet::storage::StoragePointerWriteAccess;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_utils::cryptography::nonces::NoncesComponent;
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::asset::{Asset, AssetId, AssetTrait};
    use perpetuals::core::types::node::{CollateralNode, SyntheticNode};
    use perpetuals::core::types::{PositionData, Signature};
    use perpetuals::errors::{ErrorTrait, assert_with_error, OptionErrorImpl};
    use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
    use starknet::ContractAddress;
    use starknet::storage::{Map, Vec, StoragePathEntry};

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesComponentInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        assets: Map<AssetId, Option<Asset>>,
        // TODO: consider changing the map value to bool if possible
        fulfillment: Map<felt252, Option<u64>>,
        erc20_dispatcher: IERC20Dispatcher,
        // position_id to Position
        positions: Map<felt252, Position>,
        // Valid oracles for each Asset
        oracles: Map<AssetId, Vec<ContractAddress>>,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        value_risk_calculator_dispatcher: IValueRiskCalculatorDispatcher
    }

    #[starknet::storage_node]
    struct Position {
        version: u8,
        // Iterateble map of collateral asset.
        collateral_assets: Map<AssetId, CollateralNode>,
        owner: ContractAddress,
        // Iterateble map of synthetic asset.
        synthetic_assets: Map<AssetId, SyntheticNode>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        NoncesEvent: NoncesComponent::Event
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        token_address: ContractAddress,
        value_risk_calculator: ContractAddress
    ) {
        self.erc20_dispatcher.write(IERC20Dispatcher { contract_address: token_address });
        self
            .value_risk_calculator_dispatcher
            .write(IValueRiskCalculatorDispatcher { contract_address: value_risk_calculator });
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
            expiry: TimeStamp,
            amount: u128,
            salt: felt252,
            signature: Signature
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

        fn _validate_amounts(self: @ContractState) -> bool {
            // TODO: Implement
            true
        }
        fn _validate_assets(self: @ContractState, asset_ids: Array<AssetId>) {
            for id in asset_ids {
                assert_with_error(self._get_asset(id).is_active(), CoreErrors::ASSET_NOT_ACTIVE);
            };
        }

        fn _validate_signature(
            self: @ContractState, owner: ContractAddress, hash: felt252, signature: Signature
        ) {
            let is_valid_signature_felt = ISRC6Dispatcher { contract_address: owner }
                .is_valid_signature(hash, signature);
            // Check either 'VALID' or true for backwards compatibility.
            let signature_valid = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;
            assert_with_error(signature_valid, CoreErrors::INVALID_SIGNATURE);
        }

        fn _validate_arithmetic_overflow(self: @ContractState) -> bool {
            // TODO: Implement
            true
        }

        fn _validate_fulfillment(self: @ContractState, hash: felt252) {
            assert_with_error(self.fulfillment.read(hash).is_none(), CoreErrors::ALREADY_FULFILLED);
        }

        fn _get_position(self: @ContractState, position_id: felt252) -> PositionData {
            let position = self.positions.entry(position_id);
            // TODO: Implement the 'asset_entries' field.
            PositionData {
                version: position.version.read(),
                owner: position.owner.read(),
                asset_entries: array![].span()
            }
        }

        fn _get_asset(self: @ContractState, id: AssetId) -> Asset {
            self.assets.read(id).unwrap_with_error(CoreErrors::ASSET_NOT_EXISTS)
        }

        fn _get_collateral(self: @ContractState, id: AssetId) -> Asset {
            let asset = self.assets.read(id).unwrap_with_error(CoreErrors::COLLATERAL_NOT_EXISTS);
            assert_with_error(!asset.is_synthetic(), CoreErrors::NOT_COLLATERAL);
            assert_with_error(asset.is_active(), CoreErrors::COLLATERAL_NOT_ACTIVE);
            asset
        }

        fn _get_synthetic(self: @ContractState, id: AssetId) -> Asset {
            let asset = self.assets.read(id).unwrap_with_error(CoreErrors::SYNTHETIC_NOT_EXISTS);
            assert_with_error(asset.is_synthetic(), CoreErrors::NOT_SYNTHETIC);
            assert_with_error(asset.is_active(), CoreErrors::SYNTHETIC_NOT_ACTIVE);
            asset
        }

        fn _is_asset_exist(self: @ContractState, id: AssetId) -> bool {
            self.assets.read(id).is_some()
        }
    }

    #[derive(Drop)]
    pub enum CoreErrors {
        ALREADY_FULFILLED,
        ASSET_NOT_ACTIVE,
        ASSET_NOT_EXISTS,
        INVALID_SIGNATURE,
        COLLATERAL_NOT_EXISTS,
        NOT_COLLATERAL,
        COLLATERAL_NOT_ACTIVE,
        SYNTHETIC_NOT_EXISTS,
        NOT_SYNTHETIC,
        SYNTHETIC_NOT_ACTIVE,
    }

    pub impl CoreErrorsImpl of ErrorTrait<CoreErrors> {
        fn message(self: CoreErrors) -> ByteArray {
            match self {
                CoreErrors::ALREADY_FULFILLED => "Already fulfilled",
                CoreErrors::ASSET_NOT_ACTIVE => "Asset is not active",
                CoreErrors::ASSET_NOT_EXISTS => "Asset does not exist",
                CoreErrors::INVALID_SIGNATURE => "Invalid signature",
                CoreErrors::COLLATERAL_NOT_EXISTS => "Collateral does not exist",
                CoreErrors::NOT_COLLATERAL => "Asset is not a collateral",
                CoreErrors::COLLATERAL_NOT_ACTIVE => "Collateral is not active",
                CoreErrors::SYNTHETIC_NOT_EXISTS => "Synthetic does not exist",
                CoreErrors::NOT_SYNTHETIC => "Asset is not a synthetic",
                CoreErrors::SYNTHETIC_NOT_ACTIVE => "Synthetic is not active",
            }
        }
    }
}
