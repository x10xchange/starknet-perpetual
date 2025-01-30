/// Validate that all values in the span are within the range [from, to).
pub fn validate_range<T, +Drop<T>, +Copy<T>, +PartialOrd<T>>(from: T, to: T, span: Span<T>) {
    for value in span {
        assert(from <= *value && *value < to, 'Value is out of range');
    }
}


#[cfg(test)]
mod tests {
    use super::validate_range;

    #[test]
    fn test_validate_range_happy_flow() {
        let span: Span<u32> = array![0, 9, 1].span();
        validate_range(0, 10, span);
    }

    #[test]
    #[should_panic(expected: 'Value is out of range')]
    fn test_validate_range_out_of_range() {
        let span: Span<u32> = array![0, 10, 1].span();
        validate_range(0, 10, span);
    }

    #[test]
    fn test_validate_range_empty_span() {
        let span: Span<u32> = array![].span();
        validate_range(0, 10, span);
        validate_range(0, 0, span);
        validate_range(10, 10, span);
    }

    #[test]
    fn test_validate_range_single_value_happy_flow() {
        let span: Span<u32> = array![5].span();
        validate_range(0, 10, span);
        validate_range(5, 6, span);
    }

    #[test]
    #[should_panic(expected: 'Value is out of range')]
    fn test_validate_range_single_value_out_of_range() {
        let span: Span<u32> = array![10].span();
        validate_range(0, 10, span);
    }

    #[test]
    #[should_panic(expected: 'Value is out of range')]
    fn test_validate_range_to_lower_than_from() {
        let span: Span<u32> = array![5].span();
        validate_range(10, 0, span);
    }
}
