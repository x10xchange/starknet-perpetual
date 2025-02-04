use contracts_commons::test_utils::assert_expected_event_emitted;
use contracts_commons::types::PublicKey;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::events::NewPosition;
use perpetuals::core::types::PositionId;
use perpetuals::tests::constants::*;
use snforge_std::cheatcodes::events::Event;
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use starknet::ContractAddress;


pub fn assert_new_position_event_with_expected(
    spied_event: @(ContractAddress, Event),
    position_id: PositionId,
    owner_public_key: PublicKey,
    owner_account: ContractAddress,
) {
    let expected_event = NewPosition { position_id, owner_public_key, owner_account };
    assert_expected_event_emitted(
        :spied_event, :expected_event, expected_event_selector: @selector!("NewPosition"),
    );
}
