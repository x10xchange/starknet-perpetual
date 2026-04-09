use starknet::ContractAddress;

pub fn GOVERNANCE_ADMIN() -> ContractAddress {
    'GOVERNANCE_ADMIN'.try_into().unwrap()
}
pub fn APP_ROLE_ADMIN() -> ContractAddress {
    'APP_ROLE_ADMIN'.try_into().unwrap()
}
pub fn APP_GOVERNOR() -> ContractAddress {
    'APP_GOVERNOR'.try_into().unwrap()
}
pub fn PERPS_CONTRACT() -> ContractAddress {
    'PERPS_CONTRACT'.try_into().unwrap()
}
pub fn NON_PERPS_CALLER() -> ContractAddress {
    'NON_PERPS_CALLER'.try_into().unwrap()
}
pub fn COLLATERAL_OWNER() -> ContractAddress {
    'COLLATERAL_OWNER'.try_into().unwrap()
}
pub fn SECURITY_ADMIN() -> ContractAddress {
    'SECURITY_ADMIN'.try_into().unwrap()
}
pub fn SECURITY_AGENT() -> ContractAddress {
    'SECURITY_AGENT'.try_into().unwrap()
}
pub fn SECURITY_GOVERNOR() -> ContractAddress {
    'SECURITY_GOVERNOR'.try_into().unwrap()
}

pub const UPGRADE_DELAY: u64 = 0_u64;
pub const INITIAL_PROTECTION_PERCENT: u64 = 5;
pub const INITIAL_SUPPLY: u256 = 10_000_000_000_000_000;
pub const TREASURY_FUND_AMOUNT: u128 = 1_000_000;
