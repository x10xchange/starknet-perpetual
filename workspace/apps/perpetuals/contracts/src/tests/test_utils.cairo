use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::test_utils::{Deployable, TokenConfig, TokenState};
use contracts_commons::test_utils::{cheat_caller_address_once};
use contracts_commons::types::time::time::TimeDelta;
use core::num::traits::Zero;
use openzeppelin_testing::deployment::declare_and_deploy;
use perpetuals::core::core::Core;
use perpetuals::core::interface::ICoreDispatcher;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::{CollateralConfig, VERSION};
use perpetuals::core::types::{PositionId, Signature};
use perpetuals::tests::constants::*;
use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
use snforge_std::signature::KeyPair;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::test_address;
use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;

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

/// The `User` struct represents a user corresponding to a position in the state of the Core
/// contract.
#[derive(Drop, Copy)]
pub struct User {
    pub position_id: PositionId,
    pub address: ContractAddress,
    pub key_pair: KeyPair<felt252, felt252>,
    pub salt_counter: felt252,
    pub deposited_collateral: i64,
}

#[generate_trait]
pub impl UserImpl of UserTrait {
    fn sign_message(self: User, message: felt252) -> Signature {
        let (r, s) = self.key_pair.sign(message).unwrap();
        array![r, s].span()
    }
}

impl UserDefault of Default<User> {
    fn default() -> User {
        User {
            position_id: POSITION_ID,
            address: POSITION_OWNER(),
            key_pair: KEY_PAIR(),
            salt_counter: Zero::zero(),
            deposited_collateral: Zero::zero(),
        }
    }
}

#[derive(Drop)]
pub(crate) struct PerpetualsInitConfig {
    pub governance_admin: ContractAddress,
    pub app_role_admin: ContractAddress,
    pub operator: ContractAddress,
    pub funding_validation_interval: TimeDelta,
    pub collateral_cfg: CollateralCfg,
}

impl PerpetualsInitConfigDefault of Default<PerpetualsInitConfig> {
    fn default() -> PerpetualsInitConfig {
        PerpetualsInitConfig {
            governance_admin: GOVERNANCE_ADMIN(),
            app_role_admin: APP_ROLE_ADMIN(),
            operator: OPERATOR(),
            funding_validation_interval: FUNDING_VALIDATION_INTERVAL,
            collateral_cfg: CollateralCfg {
                token_cfg: TokenConfig {
                    name: COLLATERAL_NAME(),
                    symbol: COLLATERAL_SYMBOL(),
                    initial_supply: INITIAL_SUPPLY,
                    owner: COLLATERAL_OWNER(),
                },
                asset_id: ASSET_ID(),
            },
        }
    }
}

/// The 'CollateralCfg' struct represents a deployed collateral with an associated asset id.
#[derive(Drop)]
pub struct CollateralCfg {
    pub token_cfg: TokenConfig,
    pub asset_id: AssetId,
}

pub fn generate_collateral_config(token_state: @TokenState) -> CollateralConfig {
    CollateralConfig {
        version: VERSION,
        address: *token_state.address,
        quantum: COLLATERAL_QUANTUM,
        is_active: true,
        risk_factor: RISK_FACTOR(),
        quorum: COLLATERAL_QUORUM,
    }
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
#[derive(Drop)]
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

pub(crate) fn set_roles(ref state: Core::ContractState, cfg: @PerpetualsInitConfig) {
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: *cfg.governance_admin,
    );
    state.register_app_role_admin(account: *cfg.app_role_admin);
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: *cfg.app_role_admin,
    );
    state.register_operator(account: *cfg.operator);
}

pub(crate) fn deploy_value_risk_calculator_contract() -> ContractAddress {
    declare_and_deploy("ValueRiskCalculator", array![])
}
