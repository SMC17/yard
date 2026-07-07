// yard-noise-zig public API.
//
// urn: Underwater radiated-noise source-level recovery per ITTC
//      Recommended Procedure 7.5-04-04-01. Transmission loss for
//      spherical spreading plus absorption:
//        TL = 20 log10(r / r_ref) + alpha (r - r_ref)
//      with r_ref typically 1 m. Source level
//        SPL_source = SPL_measured + TL
//      reduces a hydrophone-measured SPL at range r to the standard
//      1 m source-level reference.

pub const urn = @import("urn.zig");

test {
    _ = urn;
}
