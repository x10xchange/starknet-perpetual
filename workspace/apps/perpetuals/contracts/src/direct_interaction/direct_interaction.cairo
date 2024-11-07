#[starknet::contract]
pub mod DirectInteraction {
    use perpetuals::direct_interaction::interface::IDirectInteraction;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[constructor]
    pub fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl DirectInteractionImpl of IDirectInteraction<ContractState> {}
}

