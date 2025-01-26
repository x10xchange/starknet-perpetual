use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::test_utils::{Deployable, TokenConfig, TokenState, cheat_caller_address_once};
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::time::TimeDelta;
use core::num::traits::Zero;
use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::core::Core;
use perpetuals::core::interface::ICoreDispatcher;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::{
    CollateralConfig, CollateralTimelyData, VERSION as COLLATERAL_VERSION,
};
use perpetuals::core::types::{PositionId, Signature};
use perpetuals::tests::constants::*;
use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
use snforge_std::signature::KeyPair;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::{ContractClassTrait, DeclareResultTrait, test_address};
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
            position_id: POSITION_ID_1,
            address: deploy_account(key_pair: KEY_PAIR_1()),
            key_pair: KEY_PAIR_1(),
            salt_counter: Zero::zero(),
        }
    }
}

#[derive(Drop)]
pub(crate) struct PerpetualsInitConfig {
    pub governance_admin: ContractAddress,
    pub app_role_admin: ContractAddress,
    pub operator: ContractAddress,
    pub max_funding_interval: TimeDelta,
    pub max_price_interval: TimeDelta,
    pub max_funding_rate: u32,
    pub collateral_cfg: CollateralCfg,
    pub synthetic_cfg: SyntheticCfg,
}

impl PerpetualsInitConfigDefault of Default<PerpetualsInitConfig> {
    fn default() -> PerpetualsInitConfig {
        PerpetualsInitConfig {
            governance_admin: GOVERNANCE_ADMIN(),
            app_role_admin: APP_ROLE_ADMIN(),
            operator: OPERATOR(),
            max_funding_interval: MAX_FUNDING_INTERVAL,
            max_price_interval: MAX_PRICE_INTERVAL,
            max_funding_rate: MAX_FUNDING_RATE,
            collateral_cfg: CollateralCfg {
                token_cfg: TokenConfig {
                    name: COLLATERAL_NAME(),
                    symbol: COLLATERAL_SYMBOL(),
                    initial_supply: INITIAL_SUPPLY,
                    owner: COLLATERAL_OWNER(),
                },
                asset_id: COLLATERAL_ASSET_ID(),
                version: COLLATERAL_VERSION,
                quantum: COLLATERAL_QUANTUM,
                risk_factor: Zero::zero(),
                quorum: COLLATERAL_QUORUM,
            },
            synthetic_cfg: SyntheticCfg { asset_id: SYNTHETIC_ASSET_ID_1() },
        }
    }
}

/// The 'CollateralCfg' struct represents a deployed collateral with an associated asset id.
#[derive(Drop)]
pub struct CollateralCfg {
    pub token_cfg: TokenConfig,
    pub asset_id: AssetId,
    pub version: u8,
    pub quantum: u64,
    pub risk_factor: FixedTwoDecimal,
    pub quorum: u8,
}

/// The 'SyntheticCfg' struct represents a synthetic asset config with an associated asset id.
#[derive(Drop)]
pub struct SyntheticCfg {
    pub asset_id: AssetId,
}

pub fn generate_collateral(
    collateral_cfg: @CollateralCfg, token_state: @TokenState,
) -> (CollateralConfig, CollateralTimelyData) {
    (
        CollateralConfig {
            version: *collateral_cfg.version,
            token_address: *token_state.address,
            quantum: *collateral_cfg.quantum,
            is_active: true,
            risk_factor: *collateral_cfg.risk_factor,
            quorum: *collateral_cfg.quorum,
        },
        COLLATERAL_TIMELY_DATA(),
    )
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

fn deploy_account(key_pair: StarkKeyPair) -> ContractAddress {
    let calldata = array![key_pair.public_key];
    let account_address = declare_and_deploy("AccountUpgradeable", calldata);

    account_address
}


pub(crate) fn deploy_value_risk_calculator_contract() -> ContractAddress {
    declare_and_deploy("ValueRiskCalculator", array![])
}
