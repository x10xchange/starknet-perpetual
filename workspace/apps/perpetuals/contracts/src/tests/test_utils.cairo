use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::constants::TWO_POW_32;
use contracts_commons::test_utils::{Deployable, TokenConfig, TokenState, cheat_caller_address_once};
use contracts_commons::types::Signature;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::time::TimeDelta;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::num::traits::Zero;
use core::poseidon::PoseidonTrait;
use openzeppelin::presets::interfaces::{
    AccountUpgradeableABIDispatcher, AccountUpgradeableABIDispatcherTrait,
};
use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::core::Core;
use perpetuals::core::interface::ICoreDispatcher;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::{
    CollateralConfig, CollateralTimelyData, VERSION as COLLATERAL_VERSION,
};
use perpetuals::core::types::price::SignedPrice;
use perpetuals::tests::constants::*;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::{ContractClassTrait, DeclareResultTrait, test_address};
use starknet::ContractAddress;


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
pub(crate) struct PerpetualsInitConfig {
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


/// The `SystemConfig` struct represents the configuration settings for the entire system.
/// It includes configurations for the token, core,
#[derive(Drop)]
struct SystemConfig {
    pub token: TokenConfig,
    pub core: CoreConfig,
}

/// The `SystemState` struct represents the state of the entire system.
/// It includes the state for the token, staking, minting curve, and reward supplier contracts,
/// as well as a base account identifier.
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


pub(crate) fn set_roles(ref state: Core::ContractState, cfg: @PerpetualsInitConfig) {
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
