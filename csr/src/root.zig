// yard-csr-zig public API.
//
// section_check: Per-loading-condition section-modulus check.
// hull_girder:   CSR-H Section 5 wave coefficient C, hogging /
//                sagging / horizontal wave-bending moments; Section
//                6 ultimate-strength check.

pub const section_check = @import("section_check.zig");
pub const hull_girder = @import("hull_girder.zig");

test {
    _ = section_check;
    _ = hull_girder;
}
