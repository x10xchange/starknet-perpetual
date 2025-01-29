use core::num::traits::{One, Zero};
use perpetuals::core::types::balance::Balance;

// 2^28
pub const TWO_POW_28: u64 = 0x10000000;

// 2^56
const LIMIT: u64 = 0x100000000000000;

#[derive(Copy, Debug, Default, Drop, PartialEq, Serde, starknet::Store)]
pub struct Price {
    // Unsigned 28-bit fixed point decimal precision.
    // 28-bit for the integer part and 28-bit for the fractional part.
    value: u64,
}


pub fn validate_median_price(price_list: Span<Price>, target_price: Price) {
    let mut lower_amount: usize = 0;
    let mut higher_amount: usize = 0;
    let mut equal_amount: usize = 0;
    for price in price_list {
        if *price < target_price {
            lower_amount += 1;
        } else if *price > target_price {
            higher_amount += 1;
        } else {
            equal_amount += 1;
        }
    };
    assert(2 * (lower_amount + equal_amount) >= price_list.len(), 'TARGET_PRICE_IS_NOT_MEDIAN');
    assert(2 * (higher_amount + equal_amount) >= price_list.len(), 'TARGET_PRICE_IS_NOT_MEDIAN');
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

pub impl PriceOneImpl of One<Price> {
    fn one() -> Price {
        Price { value: TWO_POW_28 }
    }

    fn is_one(self: @Price) -> bool {
        *self.value == TWO_POW_28
    }

    fn is_non_one(self: @Price) -> bool {
        !self.value.is_one()
    }
}

#[cfg(test)]
mod tests {
    use core::num::traits::Zero;
    use perpetuals::core::types::balance::BalanceTrait;
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


    #[test]
    fn test_validate_median_price_odd_length_happy_flow() {
        let price_list = array![
            PriceTrait::new(450),
            PriceTrait::new(150),
            PriceTrait::new(350),
            PriceTrait::new(250),
            PriceTrait::new(50),
        ]
            .span();
        let target_price = PriceTrait::new(250);
        validate_median_price(:price_list, :target_price);
    }

    #[test]
    #[should_panic(expected: 'TARGET_PRICE_IS_NOT_MEDIAN')]
    fn test_validate_median_price_odd_length_bad_flow() {
        let price_list = array![
            PriceTrait::new(450),
            PriceTrait::new(150),
            PriceTrait::new(350),
            PriceTrait::new(250),
            PriceTrait::new(50),
        ]
            .span();
        let target_price = PriceTrait::new(240);
        validate_median_price(:price_list, :target_price);
    }

    #[test]
    fn test_validate_median_price_even_length_happy_flow() {
        let price_list = array![
            PriceTrait::new(150), PriceTrait::new(50), PriceTrait::new(250), PriceTrait::new(350),
        ]
            .span();
        let mut target_price = PriceTrait::new(200);
        validate_median_price(:price_list, :target_price);

        target_price = PriceTrait::new(250);
        validate_median_price(:price_list, :target_price);

        target_price = PriceTrait::new(150);
        validate_median_price(:price_list, :target_price);
    }

    #[test]
    #[should_panic(expected: 'TARGET_PRICE_IS_NOT_MEDIAN')]
    fn test_validate_median_price_even_length_bad_flow() {
        let price_list = array![
            PriceTrait::new(150), PriceTrait::new(50), PriceTrait::new(250), PriceTrait::new(350),
        ]
            .span();
        let target_price = PriceTrait::new(260);
        validate_median_price(:price_list, :target_price);
    }

    #[test]
    fn test_validate_median_price_single_element() {
        let price_list = array![PriceTrait::new(100)].span();
        let target_price = PriceTrait::new(100);
        validate_median_price(:price_list, :target_price);
    }

    #[test]
    fn test_validate_median_price_duplicate_values_happy_flow() {
        let price_list = array![
            PriceTrait::new(100),
            PriceTrait::new(100),
            PriceTrait::new(200),
            PriceTrait::new(400),
            PriceTrait::new(200),
            PriceTrait::new(300),
            PriceTrait::new(400),
        ]
            .span();
        let target_price = PriceTrait::new(200);
        validate_median_price(:price_list, :target_price);
    }

    #[test]
    #[should_panic(expected: 'TARGET_PRICE_IS_NOT_MEDIAN')]
    fn test_validate_median_price_duplicate_values_bad_flow() {
        let price_list = array![
            PriceTrait::new(100),
            PriceTrait::new(200),
            PriceTrait::new(400),
            PriceTrait::new(200),
            PriceTrait::new(300),
            PriceTrait::new(400),
            PriceTrait::new(100),
        ]
            .span();
        let target_price = PriceTrait::new(250);
        validate_median_price(:price_list, :target_price);
    }

    #[test]
    fn test_validate_median_price_empty_list() {
        let price_list = array![].span();
        let target_price = PriceTrait::new(100);
        validate_median_price(:price_list, :target_price);
    }
}
