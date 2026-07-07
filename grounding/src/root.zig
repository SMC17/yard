// yard-grounding-zig public API.
//
// pedersen_zhang: Pedersen-Zhang 2000 simplified bottom-raking model.
//                 A ship at speed V striking a rigid rock of mean
//                 height h_r above the seabed produces a horizontal
//                 reaction force F_H on the bottom plating and a
//                 longitudinal raking damage extent L_damage. The
//                 simplified force-energy balance is
//                   E_kin = F_H * L_damage
//                 with E_kin = 0.5 (1 + mu_x) m V^2.
//
// minorsky_grounding: Minorsky-style grounding energy regression
//                     E_abs [MJ] = 47.1 R_T + 32.7 with R_T the
//                     volumetric damage proxy. Shares the same
//                     coefficients as the right-angle collision case.

pub const pedersen_zhang = @import("pedersen_zhang.zig");

test {
    _ = pedersen_zhang;
}
