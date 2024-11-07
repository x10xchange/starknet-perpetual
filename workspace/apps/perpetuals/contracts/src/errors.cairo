use core::panics::panic_with_byte_array;

pub trait ErrorTrait<TError> {
    fn panic(self: TError) -> core::never {
        panic_with_byte_array(@Self::message(self))
    }
    fn message(self: TError) -> ByteArray;
}

#[generate_trait]
pub impl AssertErrorImpl<TError, +ErrorTrait<TError>, +Drop<TError>> of AssertErrorTrait<TError> {
    fn assert_with_error(condition: bool, error: TError) {
        if !condition {
            error.panic()
        }
    }
}

#[generate_trait]
pub impl OptionErrorImpl<
    T, TError, +ErrorTrait<TError>, +Drop<TError>
> of OptionErrorTrait<T, TError> {
    fn expect_with_error(self: Option<T>, err: TError) -> T {
        match self {
            Option::Some(x) => x,
            Option::None => err.panic()
        }
    }
}
