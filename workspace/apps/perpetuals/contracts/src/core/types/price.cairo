use core::num::traits::{One, WideMul, Zero};
use perpetuals::core::types::balance::Balance;
use starkware_utils::math::utils::mul_wide_and_div;
use starkware_utils::types::{PublicKey, Signature};

// 2^28
pub const PRICE_SCALE: u32 = 0x10000000;
// 2^56
const MAX_PRICE: u64 = 0x100000000000000;
// Oracle always sign the price with 18 decimal places.
const ORACLE_SCALE: u256 = 1_000_000_000_000_000_000;
// StarkNet Perps scale is with 6 decimal places.
const SN_PERPS_SCALE: u256 = 1_000_000;

const MAX_PRICE_ERROR: felt252 = 'Value must be < 2^56';

#[derive(Copy, Debug, Default, Drop, PartialEq, Serde, starknet::Store)]
pub struct Price {
    // Unsigned 28-bit fixed point decimal precision.
    // 28-bit for the integer part and 28-bit for the fractional part.
    value: u64,
}


#[derive(Copy, Debug, Drop, Serde)]
pub struct SignedPrice {
    pub signature: Signature,
    pub signer_public_key: PublicKey,
    pub timestamp: u32,
    pub oracle_price: u128,
}

impl PricePartialOrd of PartialOrd<Price> {
    fn lt(lhs: Price, rhs: Price) -> bool {
        lhs.value < rhs.value
    }
}


pub trait PriceMulTrait<T> {
    /// The result type of the multiplication.
    type Target;
    fn mul(self: @Price, rhs: T) -> Self::Target;
}


impl PriceMulU32 of PriceMulTrait<u32> {
    type Target = u128;
    fn mul(self: @Price, rhs: u32) -> Self::Target {
        mul_wide_and_div(*self.value, rhs.into(), PRICE_SCALE.into())
            .expect('Price mul overflow')
            .into()
    }
}

impl PriceMulBalance of PriceMulTrait<Balance> {
    type Target = i128;
    fn mul(self: @Price, rhs: Balance) -> Self::Target {
        let value: i64 = (*self.value).try_into().unwrap();
        mul_wide_and_div(value, rhs.into(), PRICE_SCALE.into()).expect('Price mul overflow').into()
    }
}

#[generate_trait]
pub impl PriceImpl of PriceTrait {
    fn new(value: u64) -> Price {
        assert(value < MAX_PRICE, MAX_PRICE_ERROR);
        Price { value: value }
    }

    fn build(integer_part: u32, fractional_part: u32) -> Price {
        assert(fractional_part.into() < PRICE_SCALE, 'Value must be < 2^28');
        Self::new(integer_part.into() * PRICE_SCALE.into() + fractional_part.into())
    }

    fn value(self: @Price) -> u64 {
        *self.value
    }

    fn convert(self: u128, resolution: u64) -> Price {
        let mut converted_price = self.wide_mul(PRICE_SCALE.into());
        converted_price *= SN_PERPS_SCALE;
        converted_price /= resolution.into();
        converted_price /= ORACLE_SCALE;
        converted_price.into()
    }
}


impl U256IntoPrice of Into<u256, Price> {
    fn into(self: u256) -> Price {
        let value = self.try_into().expect(MAX_PRICE_ERROR);
        assert(value < MAX_PRICE, MAX_PRICE_ERROR);
        Price { value }
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
        assert(value < MAX_PRICE, MAX_PRICE_ERROR);
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
        Price { value: PRICE_SCALE.into() }
    }

    fn is_one(self: @Price) -> bool {
        *self.value == PRICE_SCALE.into()
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
        let price = PriceTrait::new(100 * PRICE_SCALE.into());
        assert!(price.value == 100 * PRICE_SCALE.into());
    }

    #[test]
    #[should_panic(expected: 'Value must be < 2^56')]
    fn test_new_price_over_limit() {
        let _price = PriceTrait::new(MAX_PRICE.into());
    }

    #[test]
    fn test_build_price() {
        let price = PriceTrait::build(100, 100);
        assert!(price.value == 100 * PRICE_SCALE.into() + 100);
    }

    #[test]
    #[should_panic(expected: 'Value must be < 2^28')]
    fn test_build_price_over_limit() {
        let _price = PriceTrait::build(100, PRICE_SCALE.into());
    }

    #[test]
    fn test_price_mul_u32() {
        let price = PriceTrait::new(100 * PRICE_SCALE.into());
        let result = price.mul(2_u32);
        assert!(result == 200_u128);
    }

    #[test]
    fn test_price_mul_balance() {
        let price = PriceTrait::new(100 * PRICE_SCALE.into());
        let balance = BalanceTrait::new(value: 2);
        let result = price.mul(balance);
        assert!(result == 200);
    }

    #[test]
    fn test_price_add() {
        let price1 = PriceTrait::new(100_u64 * PRICE_SCALE.into());
        let price2 = PriceTrait::new(200_u64 * PRICE_SCALE.into());
        let result = price1 + price2;
        assert!(result == PriceTrait::new(300_u64 * PRICE_SCALE.into()));
    }

    #[test]
    fn test_price_sub() {
        let price1 = PriceTrait::new(200_u64 * PRICE_SCALE.into());
        let price2 = PriceTrait::new(100_u64 * PRICE_SCALE.into());
        let result = price1 - price2;
        assert!(result == PriceTrait::new(100_u64 * PRICE_SCALE.into()));
    }

    #[test]
    fn test_price_add_assign() {
        let mut price1 = PriceTrait::new(100_u64 * PRICE_SCALE.into());
        let price2 = PriceTrait::new(200_u64 * PRICE_SCALE.into());
        price1 += price2;
        assert!(price1 == PriceTrait::new(300_u64 * PRICE_SCALE.into()));
    }

    #[test]
    fn test_price_sub_assign() {
        let mut price1 = PriceTrait::new(200_u64 * PRICE_SCALE.into());
        let price2 = PriceTrait::new(100_u64 * PRICE_SCALE.into());
        price1 -= price2;
        assert!(price1 == PriceTrait::new(100_u64 * PRICE_SCALE.into()));
    }

    #[test]
    fn test_price_zero() {
        let price: Price = Zero::zero();
        assert!(price.value == 0);
    }

    #[test]
    fn test_price_is_zero() {
        let price: Price = Zero::zero();
        assert!(price.is_zero());
    }

    #[test]
    fn test_price_is_non_zero() {
        let price = PriceTrait::new(100 * PRICE_SCALE.into());
        assert!(price.is_non_zero());
    }
}
