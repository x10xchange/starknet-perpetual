use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::StarkKeyPair;
use perpetuals::core::components::assets::interface::{IAssetsDispatcher, IAssetsDispatcherTrait};
use perpetuals::core::components::deposit::Deposit::deposit_hash;
use perpetuals::core::components::deposit::interface::{
    DepositStatus, IDepositDispatcher, IDepositDispatcherTrait,
};
use perpetuals::core::components::operator_nonce::interface::{
    IOperatorNonceDispatcher, IOperatorNonceDispatcherTrait,
};
use perpetuals::core::components::positions::Positions::FEE_POSITION;
use perpetuals::core::components::positions::interface::{
    IPositionsDispatcher, IPositionsDispatcherTrait,
};
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait};
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::synthetic::SyntheticAsset;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::SignedPrice;
use perpetuals::core::types::transfer::TransferArgs;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::tests::constants;
use perpetuals::tests::event_test_utils::{
    assert_deleverage_event_with_expected, assert_deposit_canceled_event_with_expected,
    assert_deposit_event_with_expected, assert_deposit_processed_event_with_expected,
    assert_trade_event_with_expected, assert_transfer_event_with_expected,
    assert_transfer_request_event_with_expected, assert_withdraw_event_with_expected,
    assert_withdraw_request_event_with_expected,
};
use perpetuals::tests::test_utils::validate_balance;
use snforge_std::cheatcodes::events::{Event, EventSpy, EventSpyTrait, EventsFilterTrait};
use snforge_std::signature::stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl};
use snforge_std::{ContractClassTrait, DeclareResultTrait, start_cheat_block_timestamp_global};
use starknet::ContractAddress;
use starkware_utils::components::request_approvals::interface::{
    IRequestApprovalsDispatcher, IRequestApprovalsDispatcherTrait, RequestStatus,
};
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils::constants::{DAY, HOUR, MINUTE, TEN_POW_15, TWO_POW_32, TWO_POW_40};
use starkware_utils::message_hash::OffchainMessageHash;
use starkware_utils::test_utils::{
    Deployable, TokenConfig, TokenState, TokenTrait, cheat_caller_address_once,
};
use starkware_utils::types::time::time::{Time, TimeDelta, Timestamp};
use starkware_utils::types::{PublicKey, Signature};

const TIME_STEP: u64 = MINUTE;
const BEGINNING_OF_TIME: u64 = DAY * 365 * 50;

pub struct DepositInfo {
    depositor: Account,
    position_id: PositionId,
    quantized_amount: u64,
    salt: felt252,
}

pub struct RequestInfo {
    recipient: User,
    position_id: PositionId,
    amount: u64,
    expiration: Timestamp,
    salt: felt252,
    request_hash: felt252,
}

pub struct OrderInfo {
    order: Order,
    signature: Signature,
    hash: felt252,
}

/// Account is a representation of any user account that can interact with the contracts.
#[derive(Copy, Drop)]
struct Account {
    pub address: ContractAddress,
    pub key_pair: StarkKeyPair,
}

#[generate_trait]
impl AccountImpl of AccountTrait {
    fn new(secret_key: felt252) -> Account {
        let key_pair = StarkCurveKeyPairImpl::from_secret_key(secret_key);
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

#[derive(Copy, Drop)]
pub struct User {
    pub position_id: PositionId,
    pub account: Account,
    initial_balance: u64,
    salt: felt252,
}

#[generate_trait]
pub impl UserTraitImpl of UserTrait {
    fn new(token_state: TokenState, secret_key: felt252, position_id: PositionId) -> User {
        let account = AccountTrait::new(secret_key);

        let initial_balance = constants::USER_INIT_BALANCE
            .try_into()
            .expect('Value should not overflow');
        token_state.fund(account.address, initial_balance.into());

        User { position_id, account, initial_balance, salt: 0 }
    }
    fn set_as_caller(self: @User, contract_address: ContractAddress) {
        self.account.set_as_caller(:contract_address);
    }
    fn generate_salt(ref self: User) -> felt252 {
        self.salt += 1;
        self.salt
    }
    fn create_order(
        ref self: User,
        base_amount: i64,
        base_asset_id: AssetId,
        quote_amount: i64,
        fee_amount: u64,
    ) -> OrderInfo {
        let expiration = Time::now().add(delta: Time::weeks(1));
        let salt = self.generate_salt();
        let order = Order {
            position_id: self.position_id,
            base_asset_id,
            base_amount,
            quote_asset_id: constants::COLLATERAL_ASSET_ID(),
            quote_amount,
            fee_asset_id: constants::COLLATERAL_ASSET_ID(),
            fee_amount,
            expiration,
            salt,
        };
        let hash = order.get_message_hash(self.account.key_pair.public_key);
        OrderInfo { order, signature: self.account.sign_message(hash), hash }
    }
}

#[derive(Copy, Drop)]
pub struct Oracle {
    account: Account,
    name: felt252,
}

#[generate_trait]
impl OracleImpl of OracleTrait {
    fn sign_price(
        self: @Oracle, oracle_price: u128, timestamp: u32, asset_name: felt252,
    ) -> SignedPrice {
        let packed_timestamp_price = (timestamp.into() + oracle_price * TWO_POW_32.into()).into();
        let oracle_name_asset_name = *self.name + asset_name * TWO_POW_40.into();
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
    collateral_id: AssetId,
    collateral_token_address: ContractAddress,
    collateral_quantum: u64,
    max_price_interval: TimeDelta,
    max_funding_interval: TimeDelta,
    max_funding_rate: u32,
    cancel_delay: TimeDelta,
    max_oracle_price_validity: TimeDelta,
    fee_position_owner_account: ContractAddress,
    fee_position_owner_public_key: PublicKey,
    insurance_fund_position_owner_account: ContractAddress,
    insurance_fund_position_owner_public_key: PublicKey,
}

#[generate_trait]
pub impl PerpetualsConfigImpl of PerpetualsConfigTrait {
    fn new(collateral_token_address: ContractAddress, collateral_quantum: u64) -> PerpetualsConfig {
        let operator = AccountTrait::new('OPERATOR');
        PerpetualsConfig {
            operator,
            governance_admin: constants::GOVERNANCE_ADMIN(),
            role_admin: constants::APP_ROLE_ADMIN(),
            app_governor: constants::APP_GOVERNOR(),
            upgrade_delay: constants::UPGRADE_DELAY,
            collateral_id: constants::COLLATERAL_ASSET_ID(),
            collateral_token_address,
            collateral_quantum,
            max_price_interval: constants::MAX_PRICE_INTERVAL,
            max_funding_interval: constants::MAX_FUNDING_INTERVAL,
            max_funding_rate: constants::MAX_FUNDING_RATE,
            cancel_delay: constants::CANCEL_DELAY,
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
        self.collateral_id.serialize(ref calldata);
        self.collateral_token_address.serialize(ref calldata);
        self.collateral_quantum.serialize(ref calldata);
        self.max_price_interval.serialize(ref calldata);
        self.max_oracle_price_validity.serialize(ref calldata);
        self.max_funding_interval.serialize(ref calldata);
        self.max_funding_rate.serialize(ref calldata);
        self.cancel_delay.serialize(ref calldata);
        self.fee_position_owner_public_key.serialize(ref calldata);
        self.insurance_fund_position_owner_public_key.serialize(ref calldata);

        let perpetuals_contract = snforge_std::declare("Core").unwrap().contract_class();
        let (address, _) = perpetuals_contract.deploy(@calldata).unwrap();
        address
    }
}

#[derive(Drop)]
pub struct SyntheticConfig {
    pub asset_name: felt252,
    pub asset_id: AssetId,
    pub risk_factor_tiers: Span<u8>,
    pub risk_factor_first_tier_boundary: u128,
    pub risk_factor_tier_size: u128,
    pub oracles: Span<Oracle>,
    pub resolution_factor: u64,
}

/// PerpetualsWrapper is the main struct that holds the state of the flow tests.
#[derive(Drop)]
pub struct PerpetualsWrapper {
    governance_admin: ContractAddress,
    role_admin: ContractAddress,
    app_governor: ContractAddress,
    pub perpetuals_contract: ContractAddress,
    token_state: TokenState,
    collateral_quantum: u64,
    collateral_id: AssetId,
    operator: Account,
    event_info: EventSpy,
}

#[generate_trait]
impl PrivateEventStateImpl of PrivateEventStateTrait {
    fn get_last_event(
        ref self: PerpetualsWrapper, contract_address: ContractAddress,
    ) -> @(ContractAddress, Event) {
        let events = self.event_info.get_events().emitted_by(contract_address).events;
        events[events.len() - 1]
    }
}

#[generate_trait]
impl PrivatePerpetualsWrapperImpl of PrivatePerpetualsWrapperTrait {
    fn get_nonce(self: @PerpetualsWrapper) -> u64 {
        let dispatcher = IOperatorNonceDispatcher { contract_address: *self.perpetuals_contract };
        self.operator.set_as_caller(*self.perpetuals_contract);
        dispatcher.get_operator_nonce()
    }

    fn set_app_governor_as_caller(self: @PerpetualsWrapper) {
        cheat_caller_address_once(
            contract_address: *self.perpetuals_contract, caller_address: *self.app_governor,
        );
    }
    fn set_app_role_admin_as_caller(self: @PerpetualsWrapper) {
        cheat_caller_address_once(
            contract_address: *self.perpetuals_contract, caller_address: *self.role_admin,
        );
    }
    fn set_governance_admin_as_caller(self: @PerpetualsWrapper) {
        cheat_caller_address_once(
            contract_address: *self.perpetuals_contract, caller_address: *self.governance_admin,
        );
    }

    fn set_roles(self: @PerpetualsWrapper) {
        let dispatcher = IRolesDispatcher { contract_address: *self.perpetuals_contract };

        self.set_governance_admin_as_caller();
        dispatcher.register_app_role_admin(*self.role_admin);

        self.set_app_role_admin_as_caller();
        dispatcher.register_app_governor(*self.app_governor);

        self.set_app_role_admin_as_caller();
        dispatcher.register_operator(account: *self.operator.address);
    }

    fn get_position_collateral_balance(
        self: @PerpetualsWrapper, position_id: PositionId,
    ) -> Balance {
        IPositionsDispatcher { contract_address: *self.perpetuals_contract }
            .get_position_assets(position_id)
            .collateral_balance
    }
}

/// FlowTestTrait is the interface for the PerpetualsWrapper struct. It is the sole way to interact
/// with the contract by calling the following wrapper functions.
#[generate_trait]
pub impl PerpetualsWrapperImpl of FlowTestTrait {
    fn init() -> PerpetualsWrapper {
        start_cheat_block_timestamp_global(BEGINNING_OF_TIME);
        let token_config = TokenConfig {
            name: constants::COLLATERAL_NAME(),
            symbol: constants::COLLATERAL_SYMBOL(),
            initial_supply: constants::INITIAL_SUPPLY,
            owner: constants::COLLATERAL_OWNER(),
        };
        let token_state = Deployable::deploy(@token_config);
        let collateral_quantum = constants::COLLATERAL_QUANTUM;
        let perpetuals_config: PerpetualsConfig = PerpetualsConfigTrait::new(
            collateral_token_address: token_state.address, :collateral_quantum,
        );
        let perpetuals_contract = Deployable::deploy(@perpetuals_config);

        PerpetualsWrapper {
            governance_admin: perpetuals_config.governance_admin,
            role_admin: perpetuals_config.role_admin,
            app_governor: perpetuals_config.app_governor,
            perpetuals_contract,
            token_state,
            collateral_quantum,
            collateral_id: perpetuals_config.collateral_id,
            operator: perpetuals_config.operator,
            event_info: snforge_std::spy_events(),
        }
    }

    fn setup(ref self: PerpetualsWrapper, synthetics: Span<SyntheticConfig>) {
        self.set_roles();
        for synthetic_config in synthetics {
            self.add_active_synthetic(synthetic_config);
        }
        advance_time(HOUR);
    }

    fn new_position(
        ref self: PerpetualsWrapper,
        position_id: PositionId,
        owner_public_key: felt252,
        owner_account: ContractAddress,
    ) {
        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        IPositionsDispatcher { contract_address: self.perpetuals_contract }
            .new_position(:operator_nonce, :position_id, :owner_public_key, :owner_account);
    }

    fn price_tick(
        ref self: PerpetualsWrapper, synthetic_config: @SyntheticConfig, oracle_price: u128,
    ) {
        let timestamp = Time::now().seconds.try_into().unwrap();
        let mut signed_prices = array![];
        for oracle in synthetic_config.oracles {
            let signed_price = oracle
                .sign_price(:oracle_price, :timestamp, asset_name: *synthetic_config.asset_name);
            signed_prices.append(signed_price);
        }
        advance_time(TIME_STEP);

        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        IAssetsDispatcher { contract_address: self.perpetuals_contract }
            .price_tick(
                :operator_nonce,
                asset_id: *synthetic_config.asset_id,
                :oracle_price,
                signed_prices: signed_prices.span(),
            );
    }

    fn deposit(
        ref self: PerpetualsWrapper,
        ref depositor: User,
        position_id: PositionId,
        quantized_amount: u64,
    ) -> DepositInfo {
        let unquantized_amount = quantized_amount * self.collateral_quantum;
        let position_id = depositor.position_id;
        let address = depositor.account.address;
        let user_balance_before = self.token_state.balance_of(account: address);
        let contract_balance_before = self.token_state.balance_of(self.perpetuals_contract);
        let now = Time::now();

        self
            .token_state
            .approve(
                owner: address,
                spender: self.perpetuals_contract,
                amount: unquantized_amount.into(),
            );
        let salt = depositor.generate_salt();

        depositor.set_as_caller(self.perpetuals_contract);
        IDepositDispatcher { contract_address: self.perpetuals_contract }
            .deposit(:position_id, :quantized_amount, :salt);

        validate_balance(
            token_state: self.token_state,
            :address,
            expected_balance: user_balance_before - unquantized_amount.into(),
        );
        validate_balance(
            token_state: self.token_state,
            address: self.perpetuals_contract,
            expected_balance: contract_balance_before + unquantized_amount.into(),
        );

        let deposit_hash = deposit_hash(
            token_address: self.token_state.address,
            depositor: address,
            :position_id,
            :quantized_amount,
            :salt,
        );
        self.validate_deposit_status(:deposit_hash, expected_status: DepositStatus::PENDING(now));

        assert_deposit_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            :position_id,
            depositing_address: address,
            :quantized_amount,
            :unquantized_amount,
            deposit_request_hash: deposit_hash,
        );

        DepositInfo { depositor: depositor.account, position_id, quantized_amount, salt }
    }

    fn cancel_deposit(ref self: PerpetualsWrapper, deposit_info: DepositInfo) {
        let DepositInfo { depositor, position_id, quantized_amount, salt } = deposit_info;
        let user_balance_before = self.token_state.balance_of(depositor.address);
        let contract_balance_before = self.token_state.balance_of(self.perpetuals_contract);

        depositor.set_as_caller(self.perpetuals_contract);
        IDepositDispatcher { contract_address: self.perpetuals_contract }
            .cancel_deposit(:position_id, :quantized_amount, :salt);
        let deposit_hash = deposit_hash(
            token_address: self.token_state.address,
            depositor: depositor.address,
            :position_id,
            :quantized_amount,
            :salt,
        );

        let unquantized_amount = quantized_amount * self.collateral_quantum;

        validate_balance(
            token_state: self.token_state,
            address: depositor.address,
            expected_balance: user_balance_before + unquantized_amount.into(),
        );
        validate_balance(
            token_state: self.token_state,
            address: self.perpetuals_contract,
            expected_balance: contract_balance_before - unquantized_amount.into(),
        );

        self.validate_deposit_status(:deposit_hash, expected_status: DepositStatus::CANCELED);

        assert_deposit_canceled_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            :position_id,
            depositing_address: depositor.address,
            :quantized_amount,
            :unquantized_amount,
            deposit_request_hash: deposit_hash,
        );
    }

    fn process_deposit(ref self: PerpetualsWrapper, deposit_info: DepositInfo) {
        let DepositInfo { depositor, position_id, quantized_amount, salt } = deposit_info;
        let collateral_balance_before = self.get_position_collateral_balance(position_id);

        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        IDepositDispatcher { contract_address: self.perpetuals_contract }
            .process_deposit(
                :operator_nonce,
                depositor: depositor.address,
                :position_id,
                :quantized_amount,
                :salt,
            );
        self
            .validate_collateral_balance(
                :position_id, expected_balance: collateral_balance_before + quantized_amount.into(),
            );

        let deposit_hash = deposit_hash(
            token_address: self.token_state.address,
            depositor: depositor.address,
            :position_id,
            :quantized_amount,
            :salt,
        );

        self.validate_deposit_status(:deposit_hash, expected_status: DepositStatus::PROCESSED);

        assert_deposit_processed_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            :position_id,
            depositing_address: depositor.address,
            :quantized_amount,
            unquantized_amount: quantized_amount * self.collateral_quantum,
            deposit_request_hash: deposit_hash,
        );
    }

    fn withdraw_request(ref self: PerpetualsWrapper, ref user: User, amount: u64) -> RequestInfo {
        let account = user.account;
        let position_id = user.position_id;
        let recipient = account.address;
        let expiration = Time::now().add(Time::seconds(10));
        let salt = user.generate_salt();

        let request_hash = WithdrawArgs {
            recipient, position_id, collateral_id: self.collateral_id, amount, expiration, salt,
        }
            .get_message_hash(public_key: account.key_pair.public_key);
        let signature = account.sign_message(message: request_hash);

        account.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .withdraw_request(:signature, :recipient, :position_id, :amount, :expiration, :salt);

        self.validate_request_approval(:request_hash, expected_status: RequestStatus::PENDING);

        assert_withdraw_request_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            :position_id,
            :recipient,
            :amount,
            expiration: expiration,
            withdraw_request_hash: request_hash,
        );

        RequestInfo { recipient: user, position_id, amount, expiration, salt, request_hash }
    }

    fn withdraw(ref self: PerpetualsWrapper, withdraw_info: RequestInfo) {
        let RequestInfo {
            recipient, position_id, amount, expiration, salt, request_hash,
        } = withdraw_info;
        let address = recipient.account.address;
        let user_balance_before = self.token_state.balance_of(account: address);
        let contract_balance_before = self.token_state.balance_of(self.perpetuals_contract);
        let position_balance_before = IPositionsDispatcher {
            contract_address: self.perpetuals_contract,
        }
            .get_position_assets(:position_id)
            .collateral_balance;

        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .withdraw(
                :operator_nonce, recipient: address, :position_id, :amount, :expiration, :salt,
            );

        self
            .validate_collateral_balance(
                :position_id, expected_balance: position_balance_before - amount.into(),
            );

        let unquantized_amount = (amount * self.collateral_quantum).into();
        validate_balance(
            token_state: self.token_state,
            :address,
            expected_balance: user_balance_before + unquantized_amount,
        );
        validate_balance(
            token_state: self.token_state,
            address: self.perpetuals_contract,
            expected_balance: contract_balance_before - unquantized_amount,
        );

        self.validate_request_approval(:request_hash, expected_status: RequestStatus::PROCESSED);

        assert_withdraw_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            :position_id,
            recipient: address,
            :amount,
            :expiration,
            withdraw_request_hash: request_hash,
        );
    }

    fn transfer_request(
        ref self: PerpetualsWrapper, ref sender: User, recipient: User, amount: u64,
    ) -> RequestInfo {
        let expiration = Time::now().add(delta: Time::weeks(1));

        let salt = sender.generate_salt();
        let transfer_args = TransferArgs {
            position_id: sender.position_id,
            salt,
            expiration,
            collateral_id: self.collateral_id,
            amount,
            recipient: recipient.position_id,
        };
        let request_hash = transfer_args
            .get_message_hash(public_key: sender.account.key_pair.public_key);
        let signature = sender.account.sign_message(message: request_hash);

        sender.account.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .transfer_request(
                signature,
                recipient: recipient.position_id,
                position_id: sender.position_id,
                :amount,
                :expiration,
                :salt,
            );

        self.validate_request_approval(:request_hash, expected_status: RequestStatus::PENDING);

        assert_transfer_request_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            position_id: sender.position_id,
            recipient: recipient.position_id,
            :amount,
            :expiration,
            transfer_request_hash: request_hash,
        );

        RequestInfo {
            recipient, position_id: sender.position_id, amount, expiration, salt, request_hash,
        }
    }

    fn transfer(ref self: PerpetualsWrapper, transfer_info: RequestInfo) {
        let RequestInfo {
            recipient, position_id, amount, expiration, salt, request_hash,
        } = transfer_info;
        let dispatcher = IPositionsDispatcher { contract_address: self.perpetuals_contract };
        let sender_balance_before = dispatcher
            .get_position_assets(position_id: position_id)
            .collateral_balance;
        let recipient_balance_before = dispatcher
            .get_position_assets(position_id: recipient.position_id)
            .collateral_balance;

        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .transfer(
                :operator_nonce,
                recipient: recipient.position_id,
                position_id: position_id,
                amount: amount,
                expiration: expiration,
                salt: salt,
            );

        self
            .validate_request_approval(
                request_hash: request_hash, expected_status: RequestStatus::PENDING,
            );

        self
            .validate_collateral_balance(
                position_id: position_id, expected_balance: sender_balance_before - amount.into(),
            );

        self
            .validate_collateral_balance(
                position_id: recipient.position_id,
                expected_balance: recipient_balance_before + amount.into(),
            );

        assert_transfer_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            position_id: position_id,
            recipient: recipient.position_id,
            :amount,
            expiration: expiration,
            transfer_request_hash: request_hash,
        );
    }

    fn trade(
        ref self: PerpetualsWrapper,
        order_info_a: OrderInfo,
        order_info_b: OrderInfo,
        base: i64,
        quote: i64,
        fee_a: u64,
        fee_b: u64,
    ) {
        let OrderInfo { order: order_a, signature: signature_a, hash: hash_a } = order_info_a;
        let OrderInfo { order: order_b, signature: signature_b, hash: hash_b } = order_info_b;
        let asset_id = order_a.base_asset_id;
        let dispatcher = IPositionsDispatcher { contract_address: self.perpetuals_contract };
        let user_a_balance_before = dispatcher
            .get_position_assets(position_id: order_a.position_id);
        let user_a_collateral_balance_before = user_a_balance_before.collateral_balance;
        let user_a_synthetic_balance_before = get_synthetic_balance(
            assets: user_a_balance_before.synthetics, :asset_id,
        );
        let user_b_balance_before = dispatcher
            .get_position_assets(position_id: order_b.position_id);
        let user_b_collateral_balance_before = user_b_balance_before.collateral_balance;
        let user_b_synthetic_balance_before = get_synthetic_balance(
            assets: user_b_balance_before.synthetics, :asset_id,
        );
        let fee_position_balance_before = dispatcher
            .get_position_assets(position_id: FEE_POSITION)
            .collateral_balance;

        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .trade(
                :operator_nonce,
                :signature_a,
                :signature_b,
                :order_a,
                :order_b,
                actual_amount_base_a: base,
                actual_amount_quote_a: quote,
                actual_fee_a: fee_a,
                actual_fee_b: fee_b,
            );

        self
            .validate_collateral_balance(
                position_id: order_a.position_id,
                expected_balance: user_a_collateral_balance_before
                    + (quote - fee_a.try_into().unwrap()).into(),
            );

        self
            .validate_collateral_balance(
                position_id: order_b.position_id,
                expected_balance: user_b_collateral_balance_before
                    - (quote + fee_b.try_into().unwrap()).into(),
            );

        self
            .validate_synthetic_balance(
                position_id: order_a.position_id,
                :asset_id,
                expected_balance: user_a_synthetic_balance_before + base.into(),
            );

        self
            .validate_synthetic_balance(
                position_id: order_b.position_id,
                :asset_id,
                expected_balance: user_b_synthetic_balance_before - base.into(),
            );

        self
            .validate_collateral_balance(
                position_id: FEE_POSITION,
                expected_balance: fee_position_balance_before + (fee_a + fee_b).into(),
            );

        assert_trade_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            order_base_asset_id: asset_id,
            order_a_position_id: order_a.position_id,
            order_a_base_amount: order_a.base_amount,
            order_a_quote_amount: order_a.quote_amount,
            fee_a_amount: order_a.fee_amount,
            order_b_position_id: order_b.position_id,
            order_b_base_amount: order_b.base_amount,
            order_b_quote_amount: order_b.quote_amount,
            fee_b_amount: order_b.fee_amount,
            actual_amount_base_a: base,
            actual_amount_quote_a: quote,
            actual_fee_a: fee_a,
            actual_fee_b: fee_b,
            order_a_hash: hash_a,
            order_b_hash: hash_b,
        );
    }

    fn liquidate(
        ref self: PerpetualsWrapper,
        liquidated_user: User,
        liquidator_order: OrderInfo,
        liquidated_base: i64,
        liquidated_quote: i64,
        liquidated_fee: u64,
        liquidator_fee: u64,
    ) {
        let OrderInfo {
            order: liquidator_order, signature: liquidator_signature, hash: _,
        } = liquidator_order;
        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);

        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .liquidate(
                :operator_nonce,
                :liquidator_signature,
                liquidated_position_id: liquidated_user.position_id,
                :liquidator_order,
                actual_amount_base_liquidated: liquidated_base,
                actual_amount_quote_liquidated: liquidated_quote,
                actual_liquidator_fee: liquidator_fee,
                liquidated_fee_amount: liquidated_fee,
            );
    }

    fn deleverage(
        ref self: PerpetualsWrapper,
        deleveraged_user: User,
        deleverager_user: User,
        base_asset_id: AssetId,
        deleveraged_base: i64,
        deleveraged_quote: i64,
    ) {
        let dispatcher = IPositionsDispatcher { contract_address: self.perpetuals_contract };
        let deleveraged_balance_before = dispatcher
            .get_position_assets(position_id: deleveraged_user.position_id);
        let deleveraged_collateral_balance_before = deleveraged_balance_before.collateral_balance;
        let deleveraged_synthetic_balance_before = get_synthetic_balance(
            assets: deleveraged_balance_before.synthetics, asset_id: base_asset_id,
        );
        let deleverager_balance_before = dispatcher
            .get_position_assets(position_id: deleverager_user.position_id);
        let deleverager_collateral_balance_before = deleverager_balance_before.collateral_balance;
        let deleverager_synthetic_balance_before = get_synthetic_balance(
            assets: deleverager_balance_before.synthetics, asset_id: base_asset_id,
        );

        let operator_nonce = self.get_nonce();
        self.operator.set_as_caller(self.perpetuals_contract);
        ICoreDispatcher { contract_address: self.perpetuals_contract }
            .deleverage(
                :operator_nonce,
                deleveraged_position_id: deleveraged_user.position_id,
                deleverager_position_id: deleverager_user.position_id,
                base_asset_id: base_asset_id,
                deleveraged_base_amount: deleveraged_base,
                deleveraged_quote_amount: deleveraged_quote,
            );

        self
            .validate_collateral_balance(
                position_id: deleveraged_user.position_id,
                expected_balance: deleveraged_collateral_balance_before + deleveraged_quote.into(),
            );

        self
            .validate_synthetic_balance(
                position_id: deleveraged_user.position_id,
                asset_id: base_asset_id,
                expected_balance: deleveraged_synthetic_balance_before + deleveraged_base.into(),
            );

        self
            .validate_collateral_balance(
                position_id: deleverager_user.position_id,
                expected_balance: deleverager_collateral_balance_before - deleveraged_quote.into(),
            );

        self
            .validate_synthetic_balance(
                position_id: deleverager_user.position_id,
                asset_id: base_asset_id,
                expected_balance: deleverager_synthetic_balance_before - deleveraged_base.into(),
            );

        assert_deleverage_event_with_expected(
            spied_event: self.get_last_event(contract_address: self.perpetuals_contract),
            deleveraged_position_id: deleveraged_user.position_id,
            deleverager_position_id: deleverager_user.position_id,
            base_asset_id: base_asset_id,
            deleveraged_base_amount: deleveraged_base,
            deleveraged_quote_amount: deleveraged_quote,
        );
    }

    fn add_active_synthetic(ref self: PerpetualsWrapper, synthetic_config: @SyntheticConfig) {
        let dispatcher = IAssetsDispatcher { contract_address: self.perpetuals_contract };
        self.set_app_governor_as_caller();
        dispatcher
            .add_synthetic_asset(
                *synthetic_config.asset_id,
                risk_factor_tiers: *synthetic_config.risk_factor_tiers,
                risk_factor_first_tier_boundary: *synthetic_config.risk_factor_first_tier_boundary,
                risk_factor_tier_size: *synthetic_config.risk_factor_tier_size,
                quorum: synthetic_config.oracles.len().try_into().unwrap(),
                resolution_factor: *synthetic_config.resolution_factor,
            );

        for oracle in synthetic_config.oracles {
            self.set_app_governor_as_caller();
            dispatcher
                .add_oracle_to_asset(
                    *synthetic_config.asset_id,
                    *oracle.account.key_pair.public_key,
                    *oracle.name,
                    *synthetic_config.asset_name,
                );
        }
        // Activate the synthetic asset.
        self.price_tick(:synthetic_config, oracle_price: TEN_POW_15.into());
    }
    /// TODO: add all the necessary functions to interact with the contract.
}

#[generate_trait]
pub impl PerpetualsWrapperValidationsImpl of FlowTestValidationsTrait {
    fn validate_request_approval(
        self: @PerpetualsWrapper, request_hash: felt252, expected_status: RequestStatus,
    ) {
        let status = IRequestApprovalsDispatcher { contract_address: *self.perpetuals_contract }
            .get_request_status(request_hash);
        assert_eq!(status, expected_status);
    }

    fn validate_deposit_status(
        self: @PerpetualsWrapper, deposit_hash: felt252, expected_status: DepositStatus,
    ) {
        let status = IDepositDispatcher { contract_address: *self.perpetuals_contract }
            .get_deposit_status(deposit_hash);
        assert_eq!(status, expected_status);
    }

    fn validate_collateral_balance(
        self: @PerpetualsWrapper, position_id: PositionId, expected_balance: Balance,
    ) {
        assert_eq!(self.get_position_collateral_balance(position_id), expected_balance);
    }

    fn validate_synthetic_balance(
        self: @PerpetualsWrapper,
        position_id: PositionId,
        asset_id: AssetId,
        expected_balance: Balance,
    ) {
        let synthetic_assets = IPositionsDispatcher { contract_address: *self.perpetuals_contract }
            .get_position_assets(:position_id)
            .synthetics;
        let synthetic_balance = get_synthetic_balance(assets: synthetic_assets, :asset_id);

        assert_eq!(synthetic_balance, expected_balance);
    }
}

pub fn advance_time(seconds: u64) {
    start_cheat_block_timestamp_global(Time::now().add(Time::seconds(seconds)).into());
}

fn get_synthetic_balance(assets: Span<SyntheticAsset>, asset_id: AssetId) -> Balance {
    for asset in assets {
        if asset.id == @asset_id {
            return asset.balance.clone();
        }
    }
    0_i64.into()
}
