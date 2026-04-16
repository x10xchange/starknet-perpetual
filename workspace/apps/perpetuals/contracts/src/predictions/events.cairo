use perpetuals::core::types::position::PositionId;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct PredictionDeposit {
    #[key]
    pub client_id: felt252,
    #[key]
    pub from_position_id: PositionId,
    pub quantized_amount: u64,
    #[key]
    pub deposit_hash: felt252,
    pub salt: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct PredictionWithdrawal {
    #[key]
    pub client_id: felt252,
    #[key]
    pub to_position_id: PositionId,
    pub quantized_amount: u64,
    #[key]
    pub withdrawal_hash: felt252,
    pub salt: felt252,
}
