// yard-stir-zig public API.
//
// dead_ship: IMO Second-Generation Intact Stability (MEPC.1/Circ.1627)
//            dead-ship-condition Vulnerability Level 1 (VL1) check.
//            A ship dead in the water in a beam wind / beam wave seaway
//            is vulnerable to capsize when the residual roll angle
//            phi_1 exceeds the deck-edge-immersion or downflooding
//            angle phi_F. The simplified VL1 envelope:
//              phi_1 = phi_0 + 1.7 phi_m
//            where phi_0 is the steady wind-heel angle and phi_m the
//            roll amplitude in the wind gust.
//
// parametric: Parametric-roll Vulnerability Level 1 check based on the
//            Mathieu stability boundary. A vessel with low GM at the
//            wave-trough and high GM at the wave-crest, sailing in
//            head / following seas, may experience parametric roll
//            when omega_e ~ 2 omega_phi.

pub const dead_ship = @import("dead_ship.zig");
pub const parametric = @import("parametric.zig");

test {
    _ = dead_ship;
    _ = parametric;
}
