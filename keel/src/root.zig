// yard-keel-zig public API.
//
// appendage: Sailing-yacht keel + rudder appendage lift and induced-
//            drag coefficients per Larsson-Eliasson "Principles of
//            Yacht Design" closed forms. For a vertical foil of
//            effective aspect ratio AR = h^2 / S (with the free surface
//            acting as a mirror, doubling the geometric AR):
//              C_L = 2 pi alpha AR / (AR + 2)         (lifting-line)
//              C_Di = C_L^2 / (pi AR)                  (induced drag)
//            Total side force and induced drag follow from
//              F = 0.5 rho V^2 S C.

pub const appendage = @import("appendage.zig");

test {
    _ = appendage;
}
