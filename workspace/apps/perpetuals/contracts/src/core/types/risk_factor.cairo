use core::num::traits::zero::Zero;
use perpetuals::core::types::price::{AssetValue, AssetValueTrait};

// Fixed-point decimal with 2 decimal places.
//
// Example: 0.75 is represented as 75.
#[derive(Copy, Debug, Default, Drop, PartialEq, Serde, starknet::Store)]
pub struct RiskFactor {
    value: u16 // Stores number * 1000
}

#[derive(Copy, Debug, Default, Drop, PartialEq)]
pub struct AssetRisk {
    value: u128,
}

pub impl AssetRiskAddAssign of core::ops::AddAssign<AssetRisk, AssetRisk> {
    fn add_assign(ref self: AssetRisk, rhs: AssetRisk) {
        self.value += rhs.value;
    }
}

pub impl AssetRiskSubAssign of core::ops::SubAssign<AssetRisk, AssetRisk> {
    fn sub_assign(ref self: AssetRisk, rhs: AssetRisk) {
        self.value -= rhs.value;
    }
}

impl AssetRiskIntoU128 of Into<AssetRisk, u128> {
    fn into(self: AssetRisk) -> u128 {
        self.value
    }
}

#[generate_trait]
pub impl AssetRiskImpl of AssetRiskTrait {
    fn new(value: u128) -> AssetRisk {
        AssetRisk { value }
    }
}

const DENOMINATOR: u16 = 1000_u16;

pub trait RiskFactorMulTrait<T> {
    type Target;
    fn mul(self: @RiskFactor, rhs: T) -> Self::Target;
}

impl RiskFactorMulAssetValue of RiskFactorMulTrait<AssetValue> {
    type Target = AssetRisk;

    /// Multiplies the fixed-point value by `other` and divides by DENOMINATOR.
    /// Integer division truncates toward zero to the nearest integer.
    ///
    /// Example: RiskFactorTrait::new(750).mul(300) == 225
    /// Example: RiskFactorTrait::new(750).mul(301) == 225

    fn mul(self: @RiskFactor, rhs: AssetValue) -> Self::Target {
        let risk_factor: u16 = (*self.value).try_into().unwrap();
        let absolute_asset_value: u128 = rhs.into();
        let intermediate = risk_factor.into() * absolute_asset_value;
        return AssetRisk { value: intermediate / DENOMINATOR.into() };
    }
}

#[generate_trait]
pub impl RiskFactorImpl of RiskFactorTrait {
    fn new(value: u16) -> RiskFactor {
        assert(value <= DENOMINATOR, 'Value must be <= 1000');
        RiskFactor { value }
    }
}

impl RiskFactorZero of core::num::traits::Zero<RiskFactor> {
    fn zero() -> RiskFactor {
        RiskFactor { value: 0 }
    }
    fn is_zero(self: @RiskFactor) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: @RiskFactor) -> bool {
        self.value.is_non_zero()
    }
}


#[cfg(test)]
mod tests {
    use core::num::traits::zero::Zero;
    use super::{
        AssetRiskTrait, AssetValueTrait, RiskFactor, RiskFactorMulAssetValue, RiskFactorMulTrait,
        RiskFactorTrait,
    };

    #[test]
    fn test_new() {
        let d = RiskFactorTrait::new(75);
        assert_eq!(d.value, 75);
    }

    #[test]
    #[should_panic(expected: 'Value must be <= 1000')]
    fn test_new_invalid_max() {
        RiskFactorTrait::new(1001);
    }

    #[test]
    fn test_zero() {
        let d: RiskFactor = Zero::zero();
        assert_eq!(d.value, 0);
    }
    #[test]
    fn test_is_zero() {
        let d: RiskFactor = Zero::zero();
        assert!(d.is_zero());
        assert!(!d.is_non_zero());
    }
    #[test]
    fn test_is_non_zero() {
        let d: RiskFactor = RiskFactorTrait::new(1);
        assert!(d.is_non_zero());
        assert!(!d.is_zero());
    }

    #[test]
    fn test_mul() {
        assert_eq!(
            RiskFactorTrait::new(750).mul(AssetValueTrait::new(300_i128)), AssetRiskTrait::new(225),
        );
        assert_eq!(
            RiskFactorTrait::new(750).mul(AssetValueTrait::new(301_i128)), AssetRiskTrait::new(225),
        );
        assert_eq!(
            RiskFactorTrait::new(750).mul(AssetValueTrait::new(299_i128)), AssetRiskTrait::new(224),
        );
        assert_eq!(
            RiskFactorTrait::new(710).mul(AssetValueTrait::new(299_i128)), AssetRiskTrait::new(212),
        );
    }
}
