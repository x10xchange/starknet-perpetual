use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, start_cheat_block_timestamp_global};
use starknet::ContractAddress;
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils::constants::DAY;
use starkware_utils_testing::test_utils::{
    Deployable, TokenConfig, TokenState, TokenTrait, cheat_caller_address_once,
};
use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
use treasury::tests::constants::*;

const BEGINNING_OF_TIME: u64 = DAY * 365 * 50;

#[derive(Drop)]
pub struct TreasuryTestsFacade {
    pub treasury_address: ContractAddress,
    pub treasury_dispatcher: ITreasuryDispatcher,
    pub token_state: TokenState,
    pub collateral_address: ContractAddress,
    pub governance_admin: ContractAddress,
    pub app_governor: ContractAddress,
    pub role_admin: ContractAddress,
    pub perps_contract: ContractAddress,
}

#[generate_trait]
pub impl TreasuryTestsFacadeImpl of TreasuryTestsFacadeTrait {
    fn new() -> TreasuryTestsFacade {
        start_cheat_block_timestamp_global(BEGINNING_OF_TIME);

        let token_cfg = TokenConfig {
            name: "TestCollateral",
            symbol: "TC",
            initial_supply: INITIAL_SUPPLY,
            owner: COLLATERAL_OWNER(),
            decimals: 18,
        };
        let token_state = Deployable::deploy(@token_cfg);
        let collateral_address = token_state.address;

        let governance_admin = GOVERNANCE_ADMIN();
        let role_admin = APP_ROLE_ADMIN();
        let app_governor = APP_GOVERNOR();
        let perps_contract = PERPS_CONTRACT();

        // Deploy the ProtocolTreasury contract.
        let mut calldata = ArrayTrait::new();
        governance_admin.serialize(ref calldata);
        UPGRADE_DELAY.serialize(ref calldata);
        perps_contract.serialize(ref calldata);
        INITIAL_PROTECTION_PERCENT.serialize(ref calldata);

        let contract_class = snforge_std::declare("ProtocolTreasury").unwrap().contract_class();
        let (treasury_address, _) = contract_class.deploy(@calldata).unwrap();
        let treasury_dispatcher = ITreasuryDispatcher { contract_address: treasury_address };

        // Set up roles.
        let roles_dispatcher = IRolesDispatcher { contract_address: treasury_address };

        cheat_caller_address_once(
            contract_address: treasury_address, caller_address: governance_admin,
        );
        roles_dispatcher.register_app_role_admin(role_admin);

        cheat_caller_address_once(
            contract_address: treasury_address, caller_address: governance_admin,
        );
        roles_dispatcher.register_upgrade_governor(governance_admin);

        cheat_caller_address_once(
            contract_address: treasury_address, caller_address: role_admin,
        );
        roles_dispatcher.register_app_governor(app_governor);

        TreasuryTestsFacade {
            treasury_address,
            treasury_dispatcher,
            token_state,
            collateral_address,
            governance_admin,
            app_governor,
            role_admin,
            perps_contract,
        }
    }

    /// Fund the treasury with tokens.
    fn fund_treasury(ref self: TreasuryTestsFacade, amount: u128) {
        self.token_state.fund(self.treasury_address, amount.into());
    }

    /// Fund an account with tokens.
    fn fund_account(ref self: TreasuryTestsFacade, account: ContractAddress, amount: u128) {
        self.token_state.fund(account, amount.into());
    }

    /// Approve the treasury to spend tokens on behalf of caller.
    fn approve_treasury(ref self: TreasuryTestsFacade, owner: ContractAddress, amount: u128) {
        self.token_state.approve(owner, self.treasury_address, amount.into());
    }

    /// Call deposit_into as a given caller.
    fn deposit_into(ref self: TreasuryTestsFacade, caller: ContractAddress, amount: u256) {
        cheat_caller_address_once(
            contract_address: self.treasury_address, caller_address: caller,
        );
        self.treasury_dispatcher.deposit_into(self.collateral_address, amount);
    }

    /// Call withdraw_from as the perps contract.
    fn withdraw_from_as_perps(ref self: TreasuryTestsFacade, amount: u256) {
        cheat_caller_address_once(
            contract_address: self.treasury_address, caller_address: self.perps_contract,
        );
        self.treasury_dispatcher.withdraw_from(self.collateral_address, amount);
    }

    /// Call withdraw_from as a non-perps caller (should fail).
    fn withdraw_from_as_non_perps(
        ref self: TreasuryTestsFacade, caller: ContractAddress, amount: u256,
    ) {
        cheat_caller_address_once(
            contract_address: self.treasury_address, caller_address: caller,
        );
        self.treasury_dispatcher.withdraw_from(self.collateral_address, amount);
    }

    /// Call reset_protection_limit as the app governor.
    fn reset_protection_limit(ref self: TreasuryTestsFacade) {
        cheat_caller_address_once(
            contract_address: self.treasury_address, caller_address: self.app_governor,
        );
        self.treasury_dispatcher.reset_protection_limit(self.collateral_address);
    }

    /// Call change_protection_limit_percent as the app governor.
    fn change_protection_limit_percent(ref self: TreasuryTestsFacade, percent: u64) {
        cheat_caller_address_once(
            contract_address: self.treasury_address, caller_address: self.app_governor,
        );
        self
            .treasury_dispatcher
            .change_protection_limit_percent(self.collateral_address, percent);
    }

    /// Get the token balance of an address.
    fn balance_of(self: @TreasuryTestsFacade, account: ContractAddress) -> u256 {
        let erc20 = IERC20Dispatcher { contract_address: *self.collateral_address };
        erc20.balance_of(account)
    }

    /// Get the treasury's token balance.
    fn treasury_balance(self: @TreasuryTestsFacade) -> u256 {
        self.balance_of(*self.treasury_address)
    }

    /// Advance time by a given number of seconds.
    fn advance_time(ref self: TreasuryTestsFacade, seconds: u64) {
        let current = starknet::get_block_timestamp();
        start_cheat_block_timestamp_global(current + seconds);
    }
}
