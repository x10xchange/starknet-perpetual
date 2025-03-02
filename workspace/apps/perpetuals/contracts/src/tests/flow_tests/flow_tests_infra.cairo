use contracts_commons::components::deposit::interface::{
    IDepositDispatcher, IDepositDispatcherTrait,
};
use contracts_commons::components::nonce::interface::{INonceDispatcher, INonceDispatcherTrait};
use contracts_commons::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use contracts_commons::constants::{DAY, HOUR, MAX_U128, MINUTE, TWO_POW_32};
use contracts_commons::message_hash::OffchainMessageHash;
use contracts_commons::test_utils::TokenTrait;
use contracts_commons::test_utils::{Deployable, TokenConfig, TokenState, cheat_caller_address_once};
use contracts_commons::types::time::time::{Time, TimeDelta, Timestamp};
use contracts_commons::types::{PublicKey, Signature};
use core::num::traits::Zero;
use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::components::assets::interface::{IAssetsDispatcher, IAssetsDispatcherTrait};
use perpetuals::core::components::positions::interface::{
    IPositionsDispatcher, IPositionsDispatcherTrait,
};
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait};
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
use perpetuals::core::types::price::SignedPrice;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::tests::constants;
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::start_cheat_block_timestamp_global;
use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;

const TIME_STEP: u64 = MINUTE;
const BEGINNING_OF_TIME: u64 = DAY * 365 * 50;

#[derive(Drop)]
pub struct User {
    position_id: PositionId,
    account: Account,
}

#[derive(Copy, Drop)]
struct Oracle {
    account: Account,
    name: felt252,
}

#[derive(Drop)]
pub struct DepositInfo {
    // beneficiary can represent a different user than the depositor.
    user: User,
    beneficiary: u32,
    amount: u64,
    salt: felt252,
}

#[derive(Drop)]
pub struct WithdrawInfo {
    // recipient can represent a different user than the withdrawer.
    user: User,
    recipient: ContractAddress,
    amount: u64,
    expiration: Timestamp,
    salt: felt252,
}

#[generate_trait]
impl OracleImpl of OracleTrait {
    fn sign_price(
        self: @Oracle, oracle_price: u128, timestamp: u32, asset_name: felt252,
    ) -> SignedPrice {
        const TWO_POW_40: felt252 = 0x100_0000_0000;
        let packed_timestamp_price = (timestamp.into() + oracle_price * TWO_POW_32.into()).into();
        let oracle_name_asset_name = *self.name + asset_name * TWO_POW_40;
        let msg_hash = core::pedersen::pedersen(oracle_name_asset_name, packed_timestamp_price);
        SignedPrice {
            signature: self.account.sign_message(msg_hash),
            signer_public_key: *self.account.key_pair.public_key,
            timestamp,
            oracle_price,
        }
    }
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
            role_admin: constants::APP_ROLE_ADMIN(),
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
    pub key_pair: StarkKeyPair,
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

    fn sign_message(self: @Account, message: felt252) -> Signature {
        let (r, s) = (*self).key_pair.sign(message).unwrap();
        array![r, s].span()
    }
}

#[derive(Drop)]
pub struct SyntheticConfig {
    pub asset_name: felt252,
    pub asset_id: AssetId,
    pub risk_factor_tiers: Span<u8>,
    pub risk_factor_first_tier_boundary: u128,
    pub risk_factor_tier_size: u128,
    pub quorum: u8,
    pub resolution: u64,
}

pub fn create_synthetic_config(asset_name: felt252) -> SyntheticConfig {
    SyntheticConfig {
        asset_name,
        asset_id: AssetIdTrait::new(value: asset_name),
        risk_factor_tiers: array![50].span(),
        risk_factor_first_tier_boundary: MAX_U128,
        risk_factor_tier_size: Zero::zero(),
        quorum: constants::SYNTHETIC_QUORUM,
        resolution: constants::SYNTHETIC_RESOLUTION,
    }
}

/// FlowTestState is the main struct that holds the state of the flow tests.
#[derive(Drop)]
pub struct FlowTestState {
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
    salt: felt252,
}

#[generate_trait]
impl PrivateFlowTestStateImpl of PrivateFlowTestStateTrait {
    fn generate_position_id(ref self: FlowTestState) -> u32 {
        self.position_id_gen += 1;
        self.position_id_gen
    }
    fn get_nonce(self: @FlowTestState) -> u64 {
        let dispatcher = INonceDispatcher { contract_address: *self.perpetuals_contract };
        self.operator.set_as_caller(*self.perpetuals_contract);
        dispatcher.nonce()
    }

    fn set_app_governor_as_caller(self: @FlowTestState) {
        cheat_caller_address_once(
            contract_address: *self.perpetuals_contract, caller_address: *self.app_governor,
        );
    }
    fn set_app_role_admin_as_caller(self: @FlowTestState) {
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

        self.set_app_role_admin_as_caller();
        dispatcher.register_app_governor(*self.app_governor);

        self.set_app_role_admin_as_caller();
        dispatcher.register_operator(account: *self.operator.address);
    }

    fn register_collateral(self: @FlowTestState) {
        let dispatcher = IAssetsDispatcher { contract_address: *self.perpetuals_contract };

        self.set_app_governor_as_caller();
        dispatcher
            .register_collateral(
                constants::COLLATERAL_ASSET_ID(),
                *self.token_state.address,
                constants::COLLATERAL_QUANTUM,
            );
    }

    fn add_synthetic(self: @FlowTestState, synthetic_config: @SyntheticConfig) {
        let dispatcher = IAssetsDispatcher { contract_address: *self.perpetuals_contract };
        self.set_app_governor_as_caller();
        dispatcher
            .add_synthetic_asset(
                *synthetic_config.asset_id,
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
                *synthetic_config.asset_name,
            );

        self.set_app_governor_as_caller();
        dispatcher
            .add_oracle_to_asset(
                *synthetic_config.asset_id,
                *self.oracle_b.account.key_pair.public_key,
                *self.oracle_b.name,
                *synthetic_config.asset_name,
            );
    }
    fn generate_salt(ref self: FlowTestState) -> felt252 {
        self.salt += 1;
        self.salt
    }
}

/// FlowTestTrait is the interface for the FlowTestState struct. It is the sole way to interact with
/// the contract by calling the following wrapper functions.
#[generate_trait]
pub impl FlowTestStateImpl of FlowTestTrait {
    fn init() -> FlowTestState {
        start_cheat_block_timestamp_global(BEGINNING_OF_TIME);
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
                account: AccountTrait::new(ref key_gen), name: constants::ORACLE_A_NAME,
            },
            oracle_b: Oracle {
                account: AccountTrait::new(ref key_gen), name: constants::ORACLE_B_NAME,
            },
            position_id_gen: 100,
            salt: 0,
        };

        state
    }

    fn setup(ref self: FlowTestState, synthetics: Span<SyntheticConfig>) {
        self.set_roles();
        self.register_collateral();
        for synthetic_config in synthetics {
            self.add_synthetic(synthetic_config);
        };
        advance_time(HOUR);
    }

    fn new_user(ref self: FlowTestState) -> User {
        let account = AccountTrait::new(ref self.key_gen);

        self.token_state.fund(account.address, constants::USER_INIT_BALANCE);

        let operator_nonce = self.get_nonce();
        let position_id = self.generate_position_id();
        let dispatcher = IPositionsDispatcher { contract_address: self.perpetuals_contract };
        self.operator.set_as_caller(self.perpetuals_contract);
        dispatcher
            .new_position(
                operator_nonce,
                position_id: position_id.into(),
                owner_public_key: account.key_pair.public_key,
                owner_account: account.address,
            );

        User { position_id: PositionId { value: position_id }, account }
    }

    fn price_tick(ref self: FlowTestState, synthetic_config: @SyntheticConfig, oracle_price: u128) {
        let timestamp = Time::now().seconds.try_into().unwrap();
        let oracle_a_signed_price = self
            .oracle_a
            .sign_price(:oracle_price, :timestamp, asset_name: *synthetic_config.asset_name);
        let oracle_b_signed_price = self
            .oracle_b
            .sign_price(:oracle_price, :timestamp, asset_name: *synthetic_config.asset_name);
        let signed_prices = array![oracle_a_signed_price, oracle_b_signed_price].span();
        advance_time(TIME_STEP);

        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        IAssetsDispatcher { contract_address: self.perpetuals_contract }
            .price_tick(
                :operator_nonce,
                asset_id: *synthetic_config.asset_id,
                :oracle_price,
                :signed_prices,
            );
    }

    fn deposit(ref self: FlowTestState, user: User, reciever: User, amount: u128) -> DepositInfo {
        let salt = self.generate_salt();
        let beneficiary = reciever.position_id.value;
        user.account.set_as_caller(self.perpetuals_contract);
        IDepositDispatcher { contract_address: self.perpetuals_contract }
            .deposit(
                :beneficiary,
                asset_id: constants::COLLATERAL_ASSET_ID().value(),
                quantized_amount: amount,
                :salt,
            );
        DepositInfo { user, beneficiary, amount: amount.try_into().unwrap(), salt }
    }

    fn cancel_deposit(ref self: FlowTestState, deposit_info: DepositInfo) {
        deposit_info.user.account.set_as_caller(self.perpetuals_contract);
        IDepositDispatcher { contract_address: self.perpetuals_contract }
            .cancel_deposit(
                beneficiary: deposit_info.beneficiary,
                asset_id: constants::COLLATERAL_ASSET_ID().value(),
                quantized_amount: deposit_info.amount.into(),
                salt: deposit_info.salt,
            );
    }

    fn process_deposit(ref self: FlowTestState, deposit_info: DepositInfo) {
        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);

        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .process_deposit(
                :operator_nonce,
                depositor: deposit_info.user.account.address,
                position_id: deposit_info.user.position_id,
                collateral_id: constants::COLLATERAL_ASSET_ID(),
                amount: deposit_info.amount.try_into().unwrap(),
                salt: deposit_info.salt,
            );
    }

    fn deposit_in_full(ref self: FlowTestState, user: User, reciever: User, amount: u128) {
        let deposit_info = self.deposit(:user, :reciever, :amount);
        self.process_deposit(deposit_info);
    }

    fn withdraw_request(
        ref self: FlowTestState, user: User, recipient: User, amount: u128, expiration: Timestamp,
    ) -> WithdrawInfo {
        let salt = self.generate_salt();
        let recipient_address = recipient.account.address;
        let withdraw_args = WithdrawArgs {
            position_id: user.position_id,
            salt,
            expiration,
            collateral_id: constants::COLLATERAL_ASSET_ID(),
            amount: amount.try_into().unwrap(),
            recipient: recipient_address,
        };
        let msg_hash = withdraw_args.get_message_hash(public_key: user.account.key_pair.public_key);
        let signature = user.account.sign_message(message: msg_hash);

        user.account.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .withdraw_request(
                signature,
                recipient: recipient_address,
                position_id: user.position_id,
                collateral_id: constants::COLLATERAL_ASSET_ID(),
                amount: amount.try_into().unwrap(),
                :expiration,
                :salt,
            );
        WithdrawInfo {
            user,
            recipient: recipient_address,
            amount: amount.try_into().unwrap(),
            expiration,
            salt,
        }
    }

    fn withdraw(ref self: FlowTestState, withdraw_info: WithdrawInfo) {
        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .withdraw(
                :operator_nonce,
                recipient: withdraw_info.recipient,
                position_id: withdraw_info.user.position_id,
                collateral_id: constants::COLLATERAL_ASSET_ID(),
                amount: withdraw_info.amount.try_into().unwrap(),
                expiration: withdraw_info.expiration,
                salt: withdraw_info.salt,
            );
    }
    fn withdrraw_in_full(
        ref self: FlowTestState, user: User, recipient: User, amount: u128, expiration: Timestamp,
    ) {
        let withdraw_info = self.withdraw_request(:user, :recipient, :amount, :expiration);
        self.withdraw(withdraw_info);
    }
    /// TODO: add all the necessary functions to interact with the contract.
}

pub fn advance_time(seconds: u64) {
    start_cheat_block_timestamp_global(Time::now().add(Time::seconds(seconds)).into());
}
