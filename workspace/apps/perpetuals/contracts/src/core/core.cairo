#[starknet::contract]
pub mod Core {
    use contracts_commons::types::time::TimeStamp;
    use core::starknet::storage::StoragePointerWriteAccess;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use openzeppelin_account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin_utils::cryptography::nonces::NoncesComponent;
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::{AssetId, CollateralNode, SyntheticNode};
    use perpetuals::core::types::{FundingIndex, RiskFactor, Signature};
    use perpetuals::core::types::{Nonce, PositionId, PositionData};
    use perpetuals::errors::{ErrorTrait, AssertErrorImpl, OptionErrorImpl};
    use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
    use starknet::ContractAddress;
    use starknet::storage::{Map, Vec, StoragePathEntry};

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesComponentInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        assets: Map<AssetId, Asset>,
        // TODO: consider changing the map value to bool if possible
        fulfillment: Map<felt252, Option<u64>>,
        // For X10 it would be a Vec of erc20 dispatchers
        erc20_dispatcher: IERC20Dispatcher,
        positions: Map<PositionId, Position>,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        value_risk_calculator_dispatcher: IValueRiskCalculatorDispatcher
    }

    #[starknet::storage_node]
    pub struct Asset {
        version: u8,
        id: AssetId,
        name: felt252,
        decimals: u8,
        oracle_price: u64,
        risk_factor: RiskFactor,
        quorum: u8,
        oracles: Vec<ContractAddress>,
        last_funding_index: FundingIndex,
        is_active: bool
    }

    #[starknet::storage_node]
    struct Position {
        version: u8,
        // Iterateble map of collateral asset.
        collaterals_assets: Map<ContractAddress, CollateralNode>,
        // For X10 we should have another Map<AssetId, SyntheticNode> for PnL.
        owner: ContractAddress,
        // Iterateble map of synthetic asset.
        synthetics_assets: Map<AssetId, SyntheticNode>
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
            nonce: Nonce,
            expiry: TimeStamp,
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

        fn _validate_amounts(self: @ContractState) -> bool {
            // TODO: Implement
            true
        }
        fn _validate_assets(self: @ContractState) -> bool {
            // TODO: Implement
            true
        }

        fn _assert_valid_signature(
            self: @ContractState, owner: ContractAddress, hash: felt252, signature: Signature
        ) {
            let is_valid_signature_felt = ISRC6Dispatcher { contract_address: owner }
                .is_valid_signature(hash, signature);
            // Check either 'VALID' or true for backwards compatibility.
            let is_valid_signature = is_valid_signature_felt == starknet::VALIDATED
                || is_valid_signature_felt == 1;
            AssertCoreErrorImpl::assert_with_error(
                is_valid_signature, CoreErrors::INVALID_SIGNATURE
            );
        }

        fn _validate_arithmetic_overflow(self: @ContractState) -> bool {
            // TODO: Implement
            true
        }

        fn _is_already_fulfilled(self: @ContractState, hash: felt252) -> bool {
            self.fulfillment.read(hash).is_some()
        }

        fn _get_position(self: @ContractState, position_id: PositionId) -> PositionData {
            let position = self.positions.entry(position_id);
            // TODO: Implement the 'asset_entries' field.
            PositionData {
                version: position.version.read(),
                owner: position.owner.read(),
                asset_entries: array![].span()
            }
        }
    }

    #[derive(Drop)]
    pub enum CoreErrors {
        INVALID_SIGNATURE
    }
    pub impl AssertCoreErrorImpl = AssertErrorImpl<CoreErrors>;
    pub impl OptionCoreErrorTrait<T> = OptionErrorImpl<T, CoreErrors>;

    pub impl CoreErrorsImpl of ErrorTrait<CoreErrors> {
        fn message(self: CoreErrors) -> ByteArray {
            match self {
                CoreErrors::INVALID_SIGNATURE => "Invalid signature"
            }
        }
    }
}
