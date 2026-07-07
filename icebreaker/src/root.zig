// yard-icebreaker-zig public API.
//
// lindqvist: Lindqvist 1989 ice resistance for ships moving in level
//            ice. Total ice resistance R_ice = R_c + R_b + R_s, the
//            sum of crushing, bending, and submersion components, with
//            a small speed-dependent correction. Each component is a
//            closed-form expression in hull geometry (B, T, alpha,
//            phi, psi), ice properties (h_ice, sigma_f, mu, rho_diff),
//            and forward speed V.

pub const lindqvist = @import("lindqvist.zig");

test {
    _ = lindqvist;
}
