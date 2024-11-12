use core::num::traits::Zero;

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Balance {
    pub value: i128
}

impl BalanceAdd of Add<Balance> {
    fn add(lhs: Balance, rhs: Balance) -> Balance {
        Balance { value: lhs.value + rhs.value }
    }
}
impl BalanceSub of Sub<Balance> {
    fn sub(lhs: Balance, rhs: Balance) -> Balance {
        Balance { value: lhs.value - rhs.value }
    }
}

pub impl BalanceAddAssign of core::ops::AddAssign<Balance, Balance> {
    fn add_assign(ref self: Balance, rhs: Balance) {
        self.value += rhs.value;
    }
}

pub impl BalanceSubAssign of core::ops::SubAssign<Balance, Balance> {
    fn sub_assign(ref self: Balance, rhs: Balance) {
        self.value -= rhs.value;
    }
}

pub impl BalanceAddU64Assign of core::ops::AddAssign<Balance, u64> {
    fn add_assign(ref self: Balance, rhs: u64) {
        self.value += rhs.into();
    }
}

pub impl BalanceSubU64Assign of core::ops::SubAssign<Balance, u64> {
    fn sub_assign(ref self: Balance, rhs: u64) {
        self.value -= rhs.into();
    }
}

pub impl U64IntoBalance of Into<u64, Balance> {
    fn into(self: u64) -> Balance {
        Balance { value: self.into() }
    }
}

pub impl BalanceZeroImpl of Zero<Balance> {
    fn zero() -> Balance {
        Balance { value: 0 }
    }

    fn is_zero(self: @Balance) -> bool {
        self.value.is_zero()
    }

    fn is_non_zero(self: @Balance) -> bool {
        self.value.is_non_zero()
    }
}

#[generate_trait]
pub impl BalanceImpl of BalanceTrait {
    fn add(self: Balance, other: u64) -> Balance {
        Balance { value: self.value + other.into() }
    }
}

#[cfg(test)]
mod tests {
    use core::num::traits::Zero;
    use super::{Balance, BalanceTrait};

    #[test]
    fn test_add() {
        let balance1 = Balance { value: 10 };
        let balance2 = Balance { value: 5 };
        let new_balance = balance1 + balance2;
        assert!(new_balance.value == 15, "add failed");
    }

    #[test]
    fn test_sub() {
        let balance1 = Balance { value: 10 };
        let balance2 = Balance { value: 5 };
        let new_balance = balance1 - balance2;
        assert!(new_balance.value == 5, "sub failed");
    }


    #[test]
    fn test_add_assign() {
        let mut balance = Balance { value: 10 };
        balance += Balance { value: 5 };
        assert!(balance.value == 15, "add_assign failed");
    }

    #[test]
    fn test_sub_assign() {
        let mut balance = Balance { value: 10 };
        balance -= Balance { value: 5 };
        assert!(balance.value == 5, "sub_assign failed");
    }

    #[test]
    fn test_add_u64_assign() {
        let mut balance = Balance { value: 10 };
        balance += 5_u64;
        assert!(balance.value == 15, "add_assign failed");
    }

    #[test]
    fn test_sub_u64_assign() {
        let mut balance = Balance { value: 10 };
        balance -= 5_u64;
        assert!(balance.value == 5, "sub_assign failed");
    }

    #[test]
    fn test_into() {
        let balance: Balance = 10_u64.into();
        assert!(balance.value == 10, "into failed");
    }

    #[test]
    fn test_zero() {
        let balance: Balance = Zero::zero();
        assert!(balance.value == 0, "zero failed");
    }

    #[test]
    fn test_is_zero() {
        let balance = Balance { value: 0 };
        assert!(balance.is_zero(), "is_zero failed");
    }

    #[test]
    fn test_is_non_zero() {
        let balance = Balance { value: 10 };
        assert!(balance.is_non_zero(), "is_non_zero failed");
    }

    #[test]
    fn test_add_u64() {
        let balance = Balance { value: 10 };
        let new_balance = balance.add(5);
        assert!(new_balance.value == 15, "add failed");
    }
}
