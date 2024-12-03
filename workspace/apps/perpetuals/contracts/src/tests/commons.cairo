use contracts_commons::test_utils::{TokenConfig, TokenState, TokenTrait};
use perpetuals::core::interface::ICoreDispatcher;
use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;

pub(crate) mod constants {
    use contracts_commons::types::fixed_two_decimal::{FixedTwoDecimal, FixedTwoDecimalTrait};
    use perpetuals::core::types::asset::AssetId;
    use starknet::{ContractAddress, contract_address_const};


    pub fn VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS() -> ContractAddress {
        contract_address_const::<'VALUE_RISK_CALCULATOR_ADDRESS'>()
    }
    pub fn TOKEN_ADDRESS() -> ContractAddress {
        contract_address_const::<'TOKEN_ADDRESS'>()
    }
    pub fn ASSET_ID() -> AssetId {
        AssetId { value: 'asset_id' }
    }
    pub fn RISK_FACTOR() -> FixedTwoDecimal {
        FixedTwoDecimalTrait::new(50)
    }
    pub const PRICE: u64 = 900;
}


#[derive(Drop, Copy)]
pub struct CoreConfig {
    pub tv_tr_calculator: ContractAddress,
}

/// The `CoreState` struct represents the state of the Core contract.
/// It includes the contract address
#[derive(Drop, Copy)]
pub struct CoreState {
    pub address: ContractAddress,
}


#[generate_trait]
pub impl CoreImpl of CoreTrait {
    fn deploy(self: CoreConfig) -> CoreState {
        let mut calldata = array![];
        self.tv_tr_calculator.serialize(ref calldata);
        let core_contract = snforge_std::declare("Core").unwrap().contract_class();
        let (core_contract_address, _) = core_contract.deploy(@calldata).unwrap();
        let core = CoreState { address: core_contract_address };
        core
    }

    fn dispatcher(self: CoreState) -> ICoreDispatcher {
        ICoreDispatcher { contract_address: self.address }
    }
}

#[derive(Drop, Copy)]
pub struct ValueRiskCalculatorConfig {}

/// The `CoreState` struct represents the state of the Core contract.
/// It includes the contract address
#[derive(Drop, Copy)]
pub struct ValueRiskCalculatorState {
    pub address: ContractAddress,
}


#[generate_trait]
pub impl ValueRiskCalculatorImpl of ValueRiskCalculatorTrait {
    fn deploy(self: ValueRiskCalculatorConfig) -> ValueRiskCalculatorState {
        let mut calldata = array![];
        let tv_tr_calculator_contract = snforge_std::declare("ValueRiskCalculator")
            .unwrap()
            .contract_class();
        let (tv_tr_calculator_contract_address, _) = tv_tr_calculator_contract
            .deploy(@calldata)
            .unwrap();
        let tv_tr_calculator = ValueRiskCalculatorState {
            address: tv_tr_calculator_contract_address,
        };
        tv_tr_calculator
    }

    fn dispatcher(self: ValueRiskCalculatorState) -> IValueRiskCalculatorDispatcher {
        IValueRiskCalculatorDispatcher { contract_address: self.address }
    }
}


/// The `SystemConfig` struct represents the configuration settings for the entire system.
/// It includes configurations for the token, core,
#[derive(Drop, Copy)]
struct SystemConfig {
    pub token: TokenConfig,
    pub core: CoreConfig,
    pub tv_tr_calculator: ValueRiskCalculatorConfig,
}

/// The `SystemState` struct represents the state of the entire system.
/// It includes the state for the token, staking, minting curve, and reward supplier contracts,
/// as well as a base account identifier.
#[derive(Drop, Copy)]
pub struct SystemState {
    pub token: TokenState,
    pub core: CoreState,
    pub tv_tr_calculator: ValueRiskCalculatorState,
}


#[generate_trait]
pub impl SystemImpl of SystemTrait {
    /// Deploys the system configuration and returns the system state.
    fn deploy(self: SystemConfig) -> SystemState {
        let token = self.token.deploy();
        let tv_tr_calculator = self.tv_tr_calculator.deploy();
        let core = self.core.deploy();
        SystemState { token, core, tv_tr_calculator }
    }
}
