use perpetuals::core::types::position::PositionId;
use perpetuals::tests::perps_tests_facade::*;
use crate::tests::test_utils::create_token_state;


#[derive(Drop)]
pub struct TestDataState {
    pub perpetual_contract_data: PerpsTestsFacade,
    position_id_gen: u32,
    key_gen: felt252,
}

#[generate_trait]
impl PrivateTestDataStateImpl of PrivateTestDataStateTrait {
    fn generate_position_id(ref self: TestDataState) -> PositionId {
        self.position_id_gen += 1;
        PositionId { value: self.position_id_gen }
    }

    fn generate_key(ref self: TestDataState) -> felt252 {
        self.key_gen += 1;
        self.key_gen
    }
}

#[generate_trait]
pub impl TestDataStateImpl of TestDataStateTrait {
    fn new() -> TestDataState {
        TestDataState {
            perpetual_contract_data: PerpsTestsFacadeTrait::new(create_token_state()),
            position_id_gen: 100,
            key_gen: 0,
        }
    }

    fn new_user_with_position(ref self: TestDataState) -> User {
        let user = UserTrait::new(
            self.perpetual_contract_data.token_state,
            secret_key: self.generate_key(),
            position_id: self.generate_position_id(),
        );
        self
            .perpetual_contract_data
            .new_position(
                position_id: user.position_id,
                owner_public_key: user.account.key_pair.public_key,
                owner_account: user.account.address,
            );
        user
    }
}
