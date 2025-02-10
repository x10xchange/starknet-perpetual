use core::panic_with_felt252;
use core::starknet::storage_access::StorePacking;
use perpetuals::core::components::assets::errors::INVALID_STATUS;


#[derive(Copy, Debug, Drop, PartialEq, Serde)]
pub enum AssetStatus {
    PENDING,
    ACTIVATED,
    DEACTIVATED,
}

impl AssetStatusPacking of StorePacking<AssetStatus, u8> {
    fn pack(value: AssetStatus) -> u8 {
        match value {
            AssetStatus::PENDING => 0,
            AssetStatus::ACTIVATED => 1,
            AssetStatus::DEACTIVATED => 2,
        }
    }

    fn unpack(value: u8) -> AssetStatus {
        match value {
            0 => AssetStatus::PENDING,
            1 => AssetStatus::ACTIVATED,
            2 => AssetStatus::DEACTIVATED,
            _ => panic_with_felt252(INVALID_STATUS),
        }
    }
}
