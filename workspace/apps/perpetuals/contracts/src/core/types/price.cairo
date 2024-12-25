use core::num::traits::Zero;
use perpetuals::core::types::balance::{Balance, BalanceTrait};

// 2^28
pub const TWO_POW_28: u64 = 268435456;

// 2^56
const LIMIT: u64 = 72057594037927936;

#[derive(Copy, Debug, Drop, PartialEq, Serde, starknet::Store)]
pub struct Price {
    // Unsigned 28-bit fixed point decimal percision.
    // 28-bit for the integer part and 28-bit for the fractional part.
    value: u64,
}

fn mul<
    T,
    impl TMulPrice: PriceMulTrait<T>,
    +Copy<T>,
    +Drop<T>,
    +Drop<TMulPrice::Target>,
    +Div<TMulPrice::Target>,
    +Into<T, TMulPrice::Target>,
    +Into<u64, TMulPrice::Target>,
    +Mul<TMulPrice::Target>,
>(
    self: @Price, rhs: T,
) -> TMulPrice::Target {
    (*self.value).into() * rhs.into() / TWO_POW_28.into()
}

impl PricePartialord of PartialOrd<Price> {
    fn lt(lhs: Price, rhs: Price) -> bool {
        lhs.value < rhs.value
    }
}


pub trait PriceMulTrait<T> {
    /// The result type of the multiplication.
    type Target;
    fn mul(self: @Price, rhs: T) -> Self::Target;
}

impl PriceMulI128 of PriceMulTrait<i64> {
    type Target = i128;
    fn mul(self: @Price, rhs: i64) -> Self::Target {
        mul::<i64>(self, rhs)
    }
}

impl PriceMulU32 of PriceMulTrait<u32> {
    type Target = u128;
    fn mul(self: @Price, rhs: u32) -> Self::Target {
        mul::<u32>(self, rhs)
    }
}

impl PriceMulBalance of PriceMulTrait<Balance> {
    type Target = i128;
    fn mul(self: @Price, rhs: Balance) -> Self::Target {
        mul::<i64>(self, rhs.into())
    }
}

#[generate_trait]
pub impl PriceImp of PriceTrait {
    fn new(value: u64) -> Price {
        assert(value < LIMIT, 'Value must be < 2^56');
        Price { value: value }
    }

    fn value(self: @Price) -> u64 {
        *self.value
    }
}

impl PriceAdd of Add<Price> {
    fn add(lhs: Price, rhs: Price) -> Price {
        PriceTrait::new(value: lhs.value + rhs.value)
    }
}
impl PriceSub of Sub<Price> {
    fn sub(lhs: Price, rhs: Price) -> Price {
        PriceTrait::new(value: lhs.value - rhs.value)
    }
}

pub impl PriceAddAssign of core::ops::AddAssign<Price, Price> {
    fn add_assign(ref self: Price, rhs: Price) {
        let value = self.value + rhs.value;
        assert(value < LIMIT, 'Value must be < 2^56');
        self.value = value;
    }
}

pub impl PriceSubAssign of core::ops::SubAssign<Price, Price> {
    fn sub_assign(ref self: Price, rhs: Price) {
        self.value -= rhs.value;
    }
}

pub impl PriceZeroImpl of Zero<Price> {
    fn zero() -> Price {
        Price { value: 0 }
    }

    fn is_zero(self: @Price) -> bool {
        self.value.is_zero()
    }

    fn is_non_zero(self: @Price) -> bool {
        self.value.is_non_zero()
    }
}

#[cfg(test)]
mod tests {
    use core::num::traits::Zero;
    use super::*;

    #[test]
    fn test_new_price() {
        let price = PriceTrait::new(100 * TWO_POW_28);
        assert_eq!(price.value, 100 * TWO_POW_28);
    }

    #[test]
    #[should_panic(expected: 'Value must be < 2^56')]
    fn test_new_price_over_limit() {
        let _price = PriceTrait::new(LIMIT);
    }

    #[test]
    fn test_price_mul_i64() {
        let price = PriceTrait::new(100 * TWO_POW_28);
        let result = price.mul(2_i64);
        assert_eq!(result, 200);
    }

    #[test]
    fn test_price_mul_u32() {
        let price = PriceTrait::new(100 * TWO_POW_28);
        let result = price.mul(2_u32);
        assert_eq!(result, 200_u128);
    }

    #[test]
    fn test_price_mul_balance() {
        let price = PriceTrait::new(100 * TWO_POW_28);
        let balance = BalanceTrait::new(value: 2);
        let result = price.mul(balance);
        assert_eq!(result, 200);
    }

    #[test]
    fn test_price_add() {
        let price1 = PriceTrait::new(100 * TWO_POW_28);
        let price2 = PriceTrait::new(200 * TWO_POW_28);
        let result = price1 + price2;
        assert_eq!(result, PriceTrait::new(300 * TWO_POW_28));
    }

    #[test]
    fn test_price_sub() {
        let price1 = PriceTrait::new(200 * TWO_POW_28);
        let price2 = PriceTrait::new(100 * TWO_POW_28);
        let result = price1 - price2;
        assert_eq!(result, PriceTrait::new(100 * TWO_POW_28));
    }

    #[test]
    fn test_price_add_assign() {
        let mut price1 = PriceTrait::new(100 * TWO_POW_28);
        let price2 = PriceTrait::new(200 * TWO_POW_28);
        price1 += price2;
        assert_eq!(price1, PriceTrait::new(300 * TWO_POW_28));
    }

    #[test]
    fn test_price_sub_assign() {
        let mut price1 = PriceTrait::new(200 * TWO_POW_28);
        let price2 = PriceTrait::new(100 * TWO_POW_28);
        price1 -= price2;
        assert_eq!(price1, PriceTrait::new(100 * TWO_POW_28));
    }

    #[test]
    fn test_price_zero() {
        let price: Price = Zero::zero();
        assert_eq!(price.value, 0);
    }

    #[test]
    fn test_price_is_zero() {
        let price: Price = Zero::zero();
        assert!(price.is_zero());
    }

    #[test]
    fn test_price_is_non_zero() {
        let price = PriceTrait::new(100 * TWO_POW_28);
        assert!(price.is_non_zero());
    }
}
