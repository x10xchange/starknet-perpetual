use Core::InternalCoreFunctionsTrait;
use contracts_commons::components::deposit::Deposit::InternalTrait;
use contracts_commons::components::nonce::interface::INonce;
use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::constants::TWO_POW_32;
use contracts_commons::test_utils::{
    Deployable, TokenConfig, TokenState, TokenTrait, cheat_caller_address_once,
};
use contracts_commons::types::Signature;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimalTrait;
use contracts_commons::types::time::time::{TimeDelta, Timestamp};
use core::hash::{HashStateExTrait, HashStateTrait};
use core::num::traits::Zero;
use core::poseidon::PoseidonTrait;
use openzeppelin::presets::interfaces::{
    AccountUpgradeableABIDispatcher, AccountUpgradeableABIDispatcherTrait,
};
use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
use perpetuals::core::components::positions::interface::IPositions;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::ICoreDispatcher;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::{
    CollateralConfig, CollateralTimelyData, VERSION as COLLATERAL_VERSION,
};
use perpetuals::core::types::asset::status::AssetStatus;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::{Price, SignedPrice};
use perpetuals::tests::constants::*;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::{ContractClassTrait, DeclareResultTrait, test_address};
use starknet::ContractAddress;
use starknet::storage::{
    StorageMapWriteAccess, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
};


// Structs

#[derive(Drop, Copy)]
pub struct CoreConfig {}


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
    key_pair: StarkKeyPair,
    pub salt_counter: felt252,
}

pub fn get_accept_ownership_signature(
    account_address: ContractAddress, current_public_key: felt252, new_key_pair: StarkKeyPair,
) -> Signature {
    let msg_hash = PoseidonTrait::new()
        .update_with('StarkNet Message')
        .update_with('accept_ownership')
        .update_with(account_address)
        .update_with(current_public_key)
        .finalize();
    let (sig_r, sig_s) = new_key_pair.sign(msg_hash).unwrap();
    array![sig_r, sig_s].span()
}

#[generate_trait]
pub impl UserImpl of UserTrait {
    fn sign_message(self: User, message: felt252) -> Signature {
        let (r, s) = self.key_pair.sign(message).unwrap();
        array![r, s].span()
    }
    fn set_public_key(ref self: User, new_key_pair: StarkKeyPair) {
        let signature = get_accept_ownership_signature(
            self.address, self.key_pair.public_key, new_key_pair,
        );
        let dispatcher = AccountUpgradeableABIDispatcher { contract_address: self.address };
        cheat_caller_address_once(contract_address: self.address, caller_address: self.address);
        dispatcher.set_public_key(new_public_key: new_key_pair.public_key, :signature);
        self.key_pair = new_key_pair;
    }
    fn get_public_key(self: @User) -> felt252 {
        *self.key_pair.public_key
    }
    fn new(position_id: PositionId, key_pair: StarkKeyPair) -> User {
        User {
            position_id, address: deploy_account(:key_pair), key_pair, salt_counter: Zero::zero(),
        }
    }
}
impl UserDefault of Default<User> {
    fn default() -> User {
        UserTrait::new(position_id: POSITION_ID_1, key_pair: KEY_PAIR_1())
    }
}

/// The `Oracle` struct represents an oracle providing information about prices.
#[derive(Drop, Copy)]
pub struct Oracle {
    pub oracle_name: felt252,
    pub asset_name: felt252,
    pub key_pair: StarkKeyPair,
}

#[generate_trait]
pub impl OracleImpl of OracleTrait {
    fn get_oracle_name_asset_name_concat(self: @Oracle) -> felt252 {
        const TWO_POW_40: felt252 = 0x100_0000_0000;
        *self.asset_name * TWO_POW_40 + *self.oracle_name
    }
    fn get_signed_price(self: Oracle, price: u128, timestamp: u32) -> SignedPrice {
        let message = core::pedersen::pedersen(
            self.get_oracle_name_asset_name_concat(),
            (price * TWO_POW_32.into() + timestamp.into()).into(),
        );
        let (r, s) = self.key_pair.sign(message).unwrap();
        SignedPrice {
            signature: [r, s].span(), signer_public_key: self.key_pair.public_key, timestamp, price,
        }
    }
}

#[derive(Drop)]
pub struct PerpetualsInitConfig {
    pub governance_admin: ContractAddress,
    pub app_role_admin: ContractAddress,
    pub app_governor: ContractAddress,
    pub operator: ContractAddress,
    pub max_funding_interval: TimeDelta,
    pub max_price_interval: TimeDelta,
    pub max_funding_rate: u32,
    pub max_oracle_price_validity: TimeDelta,
    pub collateral_cfg: CollateralCfg,
    pub synthetic_cfg: SyntheticCfg,
}

#[generate_trait]
pub impl CoreImpl of CoreTrait {
    fn deploy(self: CoreConfig) -> CoreState {
        let mut calldata = array![];
        let core_contract = snforge_std::declare("Core").unwrap().contract_class();
        let (core_contract_address, _) = core_contract.deploy(@calldata).unwrap();
        let core = CoreState { address: core_contract_address };
        core
    }

    fn dispatcher(self: CoreState) -> ICoreDispatcher {
        ICoreDispatcher { contract_address: self.address }
    }
}


impl PerpetualsInitConfigDefault of Default<PerpetualsInitConfig> {
    fn default() -> PerpetualsInitConfig {
        PerpetualsInitConfig {
            governance_admin: GOVERNANCE_ADMIN(),
            app_role_admin: APP_ROLE_ADMIN(),
            app_governor: APP_GOVERNOR(),
            operator: OPERATOR(),
            max_funding_interval: MAX_FUNDING_INTERVAL,
            max_price_interval: MAX_PRICE_INTERVAL,
            max_funding_rate: MAX_FUNDING_RATE,
            max_oracle_price_validity: MAX_ORACLE_PRICE_VALIDITY,
            collateral_cfg: CollateralCfg {
                token_cfg: TokenConfig {
                    name: COLLATERAL_NAME(),
                    symbol: COLLATERAL_SYMBOL(),
                    initial_supply: INITIAL_SUPPLY,
                    owner: COLLATERAL_OWNER(),
                },
                collateral_id: COLLATERAL_ASSET_ID(),
                version: COLLATERAL_VERSION,
                quantum: COLLATERAL_QUANTUM,
                risk_factor: Zero::zero(),
                quorum: COLLATERAL_QUORUM,
            },
            synthetic_cfg: SyntheticCfg { synthetic_id: SYNTHETIC_ASSET_ID_1() },
        }
    }
}

/// The 'CollateralCfg' struct represents a deployed collateral with an associated asset id.
#[derive(Drop)]
pub struct CollateralCfg {
    pub token_cfg: TokenConfig,
    pub collateral_id: AssetId,
    pub version: u8,
    pub quantum: u64,
    pub risk_factor: FixedTwoDecimal,
    pub quorum: u8,
}

/// The 'SyntheticCfg' struct represents a synthetic asset config with an associated asset id.
#[derive(Drop)]
pub struct SyntheticCfg {
    pub synthetic_id: AssetId,
}

/// The `SystemConfig` struct represents the configuration settings for the entire system.
/// It includes configurations for the token, core,
#[derive(Drop)]
struct SystemConfig {
    pub token: TokenConfig,
    pub core: CoreConfig,
}

/// The `SystemState` struct represents the state of the entire system.
/// It includes the state for the token and core contracts,
#[derive(Drop, Copy)]
pub struct SystemState {
    pub token: TokenState,
    pub core: CoreState,
}

#[generate_trait]
pub impl SystemImpl of SystemTrait {
    /// Deploys the system configuration and returns the system state.
    fn deploy(self: SystemConfig) -> SystemState {
        let token = self.token.deploy();
        let core = self.core.deploy();
        SystemState { token, core }
    }
}

// Internal functions.

fn CONTRACT_STATE() -> Core::ContractState {
    Core::contract_state_for_testing()
}

fn set_roles(ref state: Core::ContractState, cfg: @PerpetualsInitConfig) {
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: *cfg.governance_admin,
    );
    state.register_app_role_admin(account: *cfg.app_role_admin);
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: *cfg.app_role_admin,
    );
    state.register_app_governor(account: *cfg.app_governor);
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

// Public functions.

pub fn setup_state_with_active_asset(
    cfg: @PerpetualsInitConfig, token_state: @TokenState,
) -> Core::ContractState {
    let mut state = init_state(:cfg, :token_state);
    // Synthetic asset configs.
    state
        .assets
        .synthetic_config
        .write(*cfg.synthetic_cfg.synthetic_id, Option::Some(SYNTHETIC_CONFIG()));
    state
        .assets
        .synthetic_timely_data
        .write(*cfg.synthetic_cfg.synthetic_id, SYNTHETIC_TIMELY_DATA());
    state.assets.synthetic_timely_data_head.write(Option::Some(*cfg.synthetic_cfg.synthetic_id));
    state.assets.num_of_active_synthetic_assets.write(1);
    state
}

pub fn setup_state_with_pending_asset(
    cfg: @PerpetualsInitConfig, token_state: @TokenState,
) -> Core::ContractState {
    let mut state = init_state(:cfg, :token_state);
    // Synthetic asset configs.
    state
        .assets
        .synthetic_config
        .write(*cfg.synthetic_cfg.synthetic_id, Option::Some(SYNTHETIC_PENDING_CONFIG()));
    state
        .assets
        .synthetic_timely_data
        .write(*cfg.synthetic_cfg.synthetic_id, SYNTHETIC_TIMELY_DATA());
    state.assets.synthetic_timely_data_head.write(Option::Some(*cfg.synthetic_cfg.synthetic_id));
    state
}

pub fn init_state(cfg: @PerpetualsInitConfig, token_state: @TokenState) -> Core::ContractState {
    let mut state = initialized_contract_state();
    set_roles(ref :state, :cfg);
    // Collateral asset configs.
    let (collateral_config, collateral_timely_data) = generate_collateral(
        collateral_cfg: cfg.collateral_cfg, :token_state,
    );
    state
        .assets
        .collateral_config
        .write(*cfg.collateral_cfg.collateral_id, Option::Some(collateral_config));
    state
        .assets
        .collateral_timely_data
        .write(*cfg.collateral_cfg.collateral_id, collateral_timely_data);
    state.assets.collateral_timely_data_head.write(Option::Some(*cfg.collateral_cfg.collateral_id));
    state
        .deposits
        .register_token(
            asset_id: (*cfg.collateral_cfg.collateral_id).into(),
            token_address: *token_state.address,
            quantum: *cfg.collateral_cfg.quantum,
        );

    // Fund the contract.
    (*token_state)
        .fund(recipient: test_address(), amount: CONTRACT_INIT_BALANCE.try_into().unwrap());

    state
}


pub fn init_position(cfg: @PerpetualsInitConfig, ref state: Core::ContractState, user: User) {
    cheat_caller_address_once(contract_address: test_address(), caller_address: *cfg.operator);
    let position_id = user.position_id;
    state
        .new_position(
            operator_nonce: state.nonce(),
            :position_id,
            owner_public_key: user.get_public_key(),
            owner_account: Zero::zero(),
        );
    let asset_id = *cfg.collateral_cfg.collateral_id;
    let asset_diff_entries = state
        ._create_position_diff(:position_id, :asset_id, diff: COLLATERAL_BALANCE_AMOUNT.into());
    state.positions.apply_diff(:position_id, :asset_diff_entries);
}

pub fn init_position_with_owner(
    cfg: @PerpetualsInitConfig, ref state: Core::ContractState, user: User,
) {
    init_position(cfg, ref :state, :user);
    let position = state.positions.get_position_mut(position_id: user.position_id);
    position.owner_account.write(user.address);
}

pub fn add_synthetic_to_position(
    ref state: Core::ContractState, asset_id: AssetId, position_id: PositionId, balance: i64,
) {
    let asset_diff_entries = state
        ._create_position_diff(:position_id, :asset_id, diff: balance.into());
    state.positions.apply_diff(:position_id, :asset_diff_entries);
}

pub fn initialized_contract_state() -> Core::ContractState {
    let mut state = CONTRACT_STATE();
    Core::constructor(
        ref state,
        governance_admin: GOVERNANCE_ADMIN(),
        upgrade_delay: UPGRADE_DELAY,
        max_price_interval: MAX_PRICE_INTERVAL,
        max_funding_interval: MAX_FUNDING_INTERVAL,
        max_funding_rate: MAX_FUNDING_RATE,
        max_oracle_price_validity: MAX_ORACLE_PRICE_VALIDITY,
        fee_position_owner_account: OPERATOR(),
        fee_position_owner_public_key: OPERATOR_PUBLIC_KEY(),
        insurance_fund_position_owner_account: OPERATOR(),
        insurance_fund_position_owner_public_key: OPERATOR_PUBLIC_KEY(),
    );
    state
}

pub fn generate_collateral(
    collateral_cfg: @CollateralCfg, token_state: @TokenState,
) -> (CollateralConfig, CollateralTimelyData) {
    (
        CollateralConfig {
            version: *collateral_cfg.version,
            token_address: *token_state.address,
            quantum: *collateral_cfg.quantum,
            status: AssetStatus::ACTIVATED,
            risk_factor: *collateral_cfg.risk_factor,
            quorum: *collateral_cfg.quorum,
        },
        COLLATERAL_TIMELY_DATA(),
    )
}

pub fn check_synthetic_config(
    state: @Core::ContractState,
    synthetic_id: AssetId,
    status: AssetStatus,
    risk_factor: u8,
    quorum: u8,
    resolution: u64,
) {
    let synthetic_config = state.assets.synthetic_config.entry(synthetic_id).read().unwrap();
    assert_eq!(synthetic_config.status, status);
    assert_eq!(synthetic_config.risk_factor, FixedTwoDecimalTrait::new(risk_factor));
    assert_eq!(synthetic_config.quorum, quorum);
    assert_eq!(synthetic_config.resolution, resolution);
}

pub fn check_synthetic_timely_data(
    state: @Core::ContractState,
    synthetic_id: AssetId,
    price: Price,
    last_price_update: Timestamp,
    funding_index: FundingIndex,
) {
    let synthetic_timely_data = state.assets.synthetic_timely_data.entry(synthetic_id).read();
    assert_eq!(synthetic_timely_data.price, price);
    assert_eq!(synthetic_timely_data.last_price_update, last_price_update);
    assert_eq!(synthetic_timely_data.funding_index, funding_index);
}

pub fn is_asset_in_synthetic_timely_data_list(
    state: @Core::ContractState, synthetic_id: AssetId,
) -> bool {
    let mut flag = false;

    let mut current_asset_id_opt = state.assets.synthetic_timely_data_head.read();
    while let Option::Some(current_asset_id) = current_asset_id_opt {
        if current_asset_id == synthetic_id {
            flag = true;
            break;
        }

        current_asset_id_opt = state
            .assets
            .synthetic_timely_data
            .entry(current_asset_id)
            .next
            .read();
    };
    flag
}

pub fn check_synthetic_asset(
    state: @Core::ContractState,
    synthetic_id: AssetId,
    status: AssetStatus,
    risk_factor: u8,
    quorum: u8,
    resolution: u64,
    price: Price,
    last_price_update: Timestamp,
    funding_index: FundingIndex,
) {
    check_synthetic_config(
        :state, :synthetic_id, status: status, :risk_factor, :quorum, :resolution,
    );
    check_synthetic_timely_data(
        :state,
        :synthetic_id,
        price: Zero::zero(),
        last_price_update: Zero::zero(),
        funding_index: Zero::zero(),
    );
    // Check the synthetic_timely_data list.
    assert!(is_asset_in_synthetic_timely_data_list(:state, :synthetic_id));
}
