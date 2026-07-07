// yard-strength-zig public API.
//
// ur_s11: IACS Unified Requirement S11 longitudinal strength.
//         Wave coefficient C piecewise across length brackets; wave
//         bending moments M_wv hog and sag; minimum section modulus
//         Z_min; minimum moment of inertia I_min; UR S4 material
//         factor k for steel grades.

pub const ur_s11 = @import("ur_s11.zig");

test {
    _ = ur_s11;
}
