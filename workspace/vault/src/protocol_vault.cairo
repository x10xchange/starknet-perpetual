use vault::interface::IProtocolVault;

const SCALE: u64 = 1000000_u64;

#[starknet::contract]
pub mod ProtocolVault {
    use ERC4626Component::Fee;
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::extensions::erc4626::{
        ERC4626Component, ERC4626DefaultNoFees, ERC4626DefaultNoLimits,
    };
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use perpetuals::core::components::positions::interface::{
        IPositionsDispatcher, IPositionsDispatcherTrait,
    };
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::math::abs::Abs;
    use super::{IProtocolVault, SCALE};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);


    #[abi(embed_v0)]
    impl ERC4626Impl = ERC4626Component::ERC4626Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC4626MetadataImpl = ERC4626Component::ERC4626MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;


    impl ERC4626InternalImpl = ERC4626Component::InternalImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        perps_contract: ContractAddress,
        owning_position_id: u32,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC4626Event: ERC4626Component::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        name: ByteArray,
        symbol: ByteArray,
        pnl_collateral_contract: ContractAddress,
        perps_contract: ContractAddress,
        owning_position_id: u32,
        recipient: ContractAddress,
        initial_price: u64,
    ) -> u256 {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);

        self.perps_contract.write(perps_contract);
        self.owning_position_id.write(owning_position_id);
        self.erc20.initializer(name, symbol);
        self.erc4626.initializer(pnl_collateral_contract);

        let total_assets = self.erc4626.get_total_assets();
        assert(total_assets > 0_u256, 'INITIAL_ASSETS_MUST_BE_POSITIVE');
        assert(recipient != perps_contract, 'RECIPIENT_CANNOT_BE_PERPS');
        assert(initial_price.is_non_zero(), 'INVALID_ZERO_INIT_PRICE');
        let amount_to_mint = (total_assets * SCALE.into()) / initial_price.into();
        self.erc20.mint(recipient, amount_to_mint);
        return total_assets;
    }

    #[abi(embed_v0)]
    pub impl Impl of IProtocolVault<ContractState> {
        fn redeem_with_price(ref self: ContractState, shares: u256, value_of_shares: u256) -> u256 {
            let perps = self.perps_contract.read();
            self
                .erc4626
                ._withdraw(
                    caller: get_caller_address(),
                    receiver: perps,
                    owner: perps,
                    assets: value_of_shares,
                    :shares,
                    fee: Option::None,
                );
            value_of_shares
        }

        fn get_owning_position_id(ref self: ContractState) -> u32 {
            self.owning_position_id.read()
        }
        fn get_perps_contract(self: @ContractState) -> ContractAddress {
            self.perps_contract.read()
        }
    }

    impl ERC4626ImmutableConfig of ERC4626Component::ImmutableConfig {
        const UNDERLYING_DECIMALS: u8 = 6;
        const DECIMALS_OFFSET: u8 = 0;
    }


    impl ERC4626ExternalAssetsManagement of ERC4626Component::AssetsManagementTrait<ContractState> {
        fn transfer_assets_in(
            ref self: ERC4626Component::ComponentState<ContractState>,
            from: ContractAddress,
            assets: u256,
        ) {// No-op: collateral is managed by the treasury, not the vault.
        // The vault only mints/burns shares; it never holds the underlying asset.
        }

        fn transfer_assets_out(
            ref self: ERC4626Component::ComponentState<ContractState>,
            to: ContractAddress,
            assets: u256,
        ) {// No-op: collateral is managed by the treasury, not the vault.
        // The vault only mints/burns shares; it never holds the underlying asset.
        }

        fn get_total_assets(self: @ERC4626Component::ComponentState<ContractState>) -> u256 {
            let asset_storage = self.get_contract().perps_contract.read();
            let asset_dispatcher = IPositionsDispatcher { contract_address: asset_storage };
            let position_tvtr = asset_dispatcher
                .get_position_tv_tr(self.get_contract().owning_position_id.read().into());

            let tv = position_tvtr.total_value;
            assert(tv >= 0, 'POSITION_HAS_NEGATIVE_TV');
            return position_tvtr.total_value.abs().into();
        }
    }


    impl ERC4626Hooks of ERC4626Component::ERC4626HooksTrait<ContractState> {
        fn before_deposit(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {
            assert(caller == self.get_contract().perps_contract.read(), 'ONLY_PERPS_CAN_DEPOSIT');
            assert(receiver == self.get_contract().perps_contract.read(), 'ONLY_PERPS_CAN_RECEIVE');
        }

        /// Hooks into `InternalImpl::_deposit`.
        /// Executes logic after transferring assets and minting shares.
        /// The fee is calculated via `FeeConfigTrait`. Assets and shares
        /// represent the actual amounts the user will spend and receive, respectively.
        /// Asset fees are included in assets; share fees are excluded from shares.
        fn after_deposit(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {}
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic before burning shares and transferring assets.
        /// The fee is calculated via `FeeConfigTrait`. Assets and shares
        /// represent the actual amounts the user will receive and spend, respectively.
        /// Asset fees are excluded from assets; share fees are included in shares.
        fn before_withdraw(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {
            assert(caller == self.get_contract().perps_contract.read(), 'ONLY_PERPS_CAN_WITHDRAW');
            assert(receiver == self.get_contract().perps_contract.read(), 'ONLY_PERPS_CAN_RECEIVE');
        }
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic after burning shares and transferring assets.
        /// The fee is calculated via `FeeConfigTrait`. Assets and shares
        /// represent the actual amounts the user will receive and spend, respectively.
        /// Asset fees are excluded from assets; share fees are included in shares.
        fn after_withdraw(
            ref self: ERC4626Component::ComponentState<ContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256,
            fee: Option<Fee>,
        ) {}
    }
}
