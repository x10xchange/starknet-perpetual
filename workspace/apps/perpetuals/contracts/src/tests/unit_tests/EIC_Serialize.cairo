use starknet::class_hash::ClassHash;


#[derive(Copy, Drop, Serde, PartialEq)]
pub struct EICData {
    pub eic_hash: ClassHash,
    pub eic_init_data: Span<felt252>,
}

/// Holds implementation data.
/// * impl_hash is the implementation class hash.
/// * eic_data is the EIC data when applicable, and empty otherwise.
/// * final indicates whether the implementation is finalized.
#[derive(Copy, Drop, Serde, PartialEq)]
pub struct ImplementationData {
    pub impl_hash: ClassHash,
    pub eic_data: Option<EICData>,
    pub final: bool,
}

#[test]
fn serialize_eic_data() {
    let eic_init_data = array![];

    let first_struct = ImplementationData {
        impl_hash: 0x07ba92f30507cb56b7cabe5c92a82ef040c7a7898f72610a8461a434643fac15
            .try_into()
            .unwrap(),
        eic_data: Option::Some(
            EICData {
                eic_hash: 0x4271f0326514808005fd470d9668163e9d2015d2505f114291be45a67241add
                    .try_into()
                    .unwrap(),
                eic_init_data: eic_init_data.span(),
            },
        ),
        final: false,
    };
    let mut output_array = array![];
    first_struct.serialize(ref output_array);

    for i in 0..output_array.len() {
        let item = output_array[i];
        println!("0x{:x}", *item);
    }
}
