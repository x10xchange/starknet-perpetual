use core::panics::panic_with_byte_array;

pub trait ErrorTrait<E> {
    fn message(self: E) -> ByteArray;
}

pub fn panic_with_error<E, +ErrorTrait<E>, +Drop<E>>(err: E) -> core::never {
    panic_with_byte_array(@err.message())
}

pub fn assert_with_error<E, +ErrorTrait<E>, +Drop<E>>(condition: bool, err: E) {
    if !condition {
        panic_with_error(err)
    }
}

#[generate_trait]
pub impl OptionErrorImpl<T, E, +ErrorTrait<E>, +Drop<E>> of OptionErrorTrait<T, E> {
    fn unwrap_with_error(self: Option<T>, err: E) -> T {
        match self {
            Option::Some(x) => x,
            Option::None => panic_with_error(err),
        }
    }
}
