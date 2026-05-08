use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct MaxDepositUpdated {
    #[key]
    pub token_address: ContractAddress,
    pub old_max: Option<u256>,
    pub new_max: Option<u256>,
}
