use contracts_commons::components::nonce::interface::{INonceDispatcher, INonceDispatcherTrait};
use contracts_commons::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use contracts_commons::test_utils::TokenTrait;
use contracts_commons::test_utils::{Deployable, TokenConfig, TokenState, cheat_caller_address_once};
use contracts_commons::types::time::time::{Time, TimeDelta};
use contracts_commons::types::{PublicKey, Signature};
use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::components::assets::interface::{IAssetsDispatcher, IAssetsDispatcherTrait};
use perpetuals::core::components::positions::interface::{
    IPositionsDispatcher, IPositionsDispatcherTrait,
};
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait};
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::start_cheat_block_timestamp_global;
use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;
use super::constants as flow_tests_constants;
use super::super::constants;

#[derive(Drop)]
struct Oracle {
    account: Account,
    name: felt252,
}

#[derive(Drop)]
struct PerpetualsConfig {
    operator: Account,
    governance_admin: ContractAddress,
    role_admin: ContractAddress,
    app_governor: ContractAddress,
    upgrade_delay: u64,
    max_price_interval: TimeDelta,
    max_funding_interval: TimeDelta,
    max_funding_rate: u32,
    max_oracle_price_validity: TimeDelta,
    fee_position_owner_account: ContractAddress,
    fee_position_owner_public_key: PublicKey,
    insurance_fund_position_owner_account: ContractAddress,
    insurance_fund_position_owner_public_key: PublicKey,
}

impl DefaultPerpetualsConfig of Default<PerpetualsConfig> {
    fn default() -> PerpetualsConfig {
        let mut key_gen = 1;
        let operator = AccountTrait::new(ref key_gen);
        PerpetualsConfig {
            operator,
            governance_admin: constants::GOVERNANCE_ADMIN(),
            role_admin: constants::ROLE_ADMIN(),
            app_governor: constants::APP_GOVERNOR(),
            upgrade_delay: constants::UPGRADE_DELAY,
            max_price_interval: constants::MAX_PRICE_INTERVAL,
            max_funding_interval: constants::MAX_FUNDING_INTERVAL,
            max_funding_rate: constants::MAX_FUNDING_RATE,
            max_oracle_price_validity: constants::MAX_ORACLE_PRICE_VALIDITY,
            fee_position_owner_account: operator.address,
            fee_position_owner_public_key: operator.key_pair.public_key,
            insurance_fund_position_owner_account: operator.address,
            insurance_fund_position_owner_public_key: operator.key_pair.public_key,
        }
    }
}

impl PerpetualsContractStateImpl of Deployable<PerpetualsConfig, ContractAddress> {
    fn deploy(self: @PerpetualsConfig) -> ContractAddress {
        let mut calldata = ArrayTrait::new();
        self.governance_admin.serialize(ref calldata);
        self.upgrade_delay.serialize(ref calldata);
        self.max_price_interval.serialize(ref calldata);
        self.max_funding_interval.serialize(ref calldata);
        self.max_funding_rate.serialize(ref calldata);
        self.max_oracle_price_validity.serialize(ref calldata);
        self.fee_position_owner_account.serialize(ref calldata);
        self.fee_position_owner_public_key.serialize(ref calldata);
        self.insurance_fund_position_owner_account.serialize(ref calldata);
        self.insurance_fund_position_owner_public_key.serialize(ref calldata);

        let perpetuals_contract = snforge_std::declare("Core").unwrap().contract_class();
        let (address, _) = perpetuals_contract.deploy(@calldata).unwrap();
        address
    }
}

/// Account is a representation of any user account that can interact with the contracts.
#[derive(Copy, Drop)]
struct Account {
    address: ContractAddress,
    key_pair: StarkKeyPair,
}

#[generate_trait]
impl AccountImpl of AccountTrait {
    fn new(ref key_gen: felt252) -> Account {
        let key_pair = StarkCurveKeyPairImpl::from_secret_key(key_gen);
        key_gen += 1;
        let address = declare_and_deploy("AccountUpgradeable", array![key_pair.public_key]);
        Account { key_pair, address }
    }

    fn set_as_caller(self: @Account, contract_address: ContractAddress) {
        cheat_caller_address_once(:contract_address, caller_address: *self.address);
    }

    fn sign_message(self: Account, message: felt252) -> Signature {
        let (r, s) = self.key_pair.sign(message).unwrap();
        array![r, s].span()
    }
}

/// FlowTestState is the main struct that holds the state of the flow tests.
#[derive(Drop)]
pub(crate) struct FlowTestState {
    governance_admin: ContractAddress,
    role_admin: ContractAddress,
    app_governor: ContractAddress,
    perpetuals_contract: ContractAddress,
    token_state: TokenState,
    key_gen: felt252,
    operator: Account,
    oracle_a: Oracle,
    oracle_b: Oracle,
    position_id_gen: u32,
}

#[generate_trait]
impl PrivateFlowTestStateImpl of PrivateFlowTestStateTrait {
    fn get_nonce(self: @FlowTestState) -> u64 {
        let dispatcher = INonceDispatcher { contract_address: *self.perpetuals_contract };
        dispatcher.nonce()
    }

    fn set_app_governor_as_caller(self: @FlowTestState) {
        cheat_caller_address_once(
            contract_address: *self.perpetuals_contract, caller_address: *self.app_governor,
        );
    }
    fn set_role_admin_as_caller(self: @FlowTestState) {
        cheat_caller_address_once(
            contract_address: *self.perpetuals_contract, caller_address: *self.role_admin,
        );
    }
    fn set_governance_admin_as_caller(self: @FlowTestState) {
        cheat_caller_address_once(
            contract_address: *self.perpetuals_contract, caller_address: *self.governance_admin,
        );
    }

    fn set_roles(self: @FlowTestState) {
        let dispatcher = IRolesDispatcher { contract_address: *self.perpetuals_contract };

        self.set_governance_admin_as_caller();
        dispatcher.register_app_role_admin(*self.role_admin);

        self.set_role_admin_as_caller();
        dispatcher.register_app_governor(*self.app_governor);

        self.set_role_admin_as_caller();
        dispatcher.register_operator(account: *self.operator.address);
    }

    fn register_collateral(self: @FlowTestState) {
        let dispatcher = ICoreDispatcher { contract_address: *self.perpetuals_contract };

        self.set_app_governor_as_caller();
        dispatcher
            .register_collateral(
                constants::COLLATERAL_ASSET_ID(),
                *self.token_state.address,
                constants::COLLATERAL_QUANTUM,
            );
    }


    fn add_synthetic(
        self: @FlowTestState, synthetic_config: @flow_tests_constants::SyntheticConfig,
    ) {
        let dispatcher = IAssetsDispatcher { contract_address: *self.perpetuals_contract };

        self.set_app_governor_as_caller();
        dispatcher
            .add_synthetic_asset(
                asset_id: *synthetic_config.asset_id,
                risk_factor_tiers: *synthetic_config.risk_factor_tiers,
                risk_factor_first_tier_boundary: *synthetic_config.risk_factor_first_tier_boundary,
                risk_factor_tier_size: *synthetic_config.risk_factor_tier_size,
                quorum: *synthetic_config.quorum,
                resolution: *synthetic_config.resolution,
            );

        self.set_app_governor_as_caller();
        dispatcher
            .add_oracle_to_asset(
                *synthetic_config.asset_id,
                *self.oracle_a.account.key_pair.public_key,
                *self.oracle_a.name,
                *synthetic_config.oracle_a_name,
            );

        self.set_app_governor_as_caller();
        dispatcher
            .add_oracle_to_asset(
                *synthetic_config.asset_id,
                *self.oracle_b.account.key_pair.public_key,
                *self.oracle_b.name,
                *synthetic_config.oracle_b_name,
            );
    }
}

/// FlowTestTrait is the interface for the FlowTestState struct. It is the sole way to interact with
/// the contract by calling the following wrapper functions.
#[generate_trait]
pub impl FlowTestStateImpl of FlowTestTrait {
    fn init() -> FlowTestState {
        start_cheat_block_timestamp_global(1000000);
        let mut key_gen = 1;
        let perpetuals_config: PerpetualsConfig = Default::default();
        let perpetuals_contract = Deployable::deploy(@perpetuals_config);

        let token_config = TokenConfig {
            name: constants::COLLATERAL_NAME(),
            symbol: constants::COLLATERAL_SYMBOL(),
            initial_supply: constants::INITIAL_SUPPLY,
            owner: constants::COLLATERAL_OWNER(),
        };
        let token_state = Deployable::deploy(@token_config);

        let mut state = FlowTestState {
            governance_admin: perpetuals_config.governance_admin,
            role_admin: perpetuals_config.role_admin,
            app_governor: perpetuals_config.app_governor,
            perpetuals_contract,
            token_state,
            key_gen,
            operator: perpetuals_config.operator,
            oracle_a: Oracle {
                account: AccountTrait::new(ref key_gen), name: flow_tests_constants::ORACLE_A_NAME,
            },
            oracle_b: Oracle {
                account: AccountTrait::new(ref key_gen), name: flow_tests_constants::ORACLE_B_NAME,
            },
            position_id_gen: 100,
        };

        state
    }

    fn setup(ref self: FlowTestState) {
        self.set_roles();
        self.register_collateral();
    }

    fn new_user(ref self: FlowTestState) -> Account {
        let new_user = AccountTrait::new(ref self.key_gen);

        self.token_state.fund(new_user.address, constants::USER_INIT_BALANCE);

        self.operator.set_as_caller(self.perpetuals_contract);
        let dispatcher = IPositionsDispatcher { contract_address: self.perpetuals_contract };
        dispatcher
            .new_position(
                operator_nonce: self.get_nonce(),
                position_id: self.position_id_gen.into(),
                owner_public_key: new_user.key_pair.public_key,
                owner_account: new_user.address,
            );
        self.position_id_gen += 1;

        new_user
    }
    /// TODO: add all the necessary functions to interact with the contract.
}

pub fn advance_time(delta: TimeDelta) {
    start_cheat_block_timestamp_global(Time::now().add(delta).into());
}
