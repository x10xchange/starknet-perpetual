use starknet::ClassHash;


pub const EXTERNAL_COMPONENT_VAULT: felt252 = 'VAULTS';
pub const EXTERNAL_COMPONENT_WITHDRAWALS: felt252 = 'WITHDRAWALS';
pub const EXTERNAL_COMPONENT_TRANSFERS: felt252 = 'TRANSFERS';
pub const EXTERNAL_COMPONENT_LIQUIDATIONS: felt252 = 'LIQUIDATIONS';
pub const EXTERNAL_COMPONENT_DELEVERAGES: felt252 = 'DELEVERAGES';

#[starknet::interface]
pub trait IExternalComponents<TContractState> {

    fn register_external_component(
        ref self: TContractState,
        component_type: felt252,
        component_address: ClassHash,
    );

    fn activate_external_component(
        ref self: TContractState,
        component_type: felt252,
        component_address: ClassHash,
    );


    // fn register_vault_component(ref self: TContractState, component_address: ClassHash);
    // fn register_withdraw_component(ref self: TContractState, component_address: ClassHash);
    // fn register_transfer_component(ref self: TContractState, component_address: ClassHash);
    // fn register_liquidation_component(ref self: TContractState, component_address: ClassHash);
    // fn register_deleverage_component(ref self: TContractState, component_address: ClassHash);

    // fn activate_vault_component(ref self: TContractState, component_address: ClassHash);
    // fn activate_withdraw_component(ref self: TContractState, component_address: ClassHash);
    // fn activate_transfer_component(ref self: TContractState, component_address: ClassHash);
    // fn activate_liquidation_component(ref self: TContractState, component_address: ClassHash);
    // fn activate_deleverage_component(ref self: TContractState, component_address: ClassHash);    
}

