// yard-azipod-zig public API.
//
// azipod:  Azimuthing thruster (Azipod) steering-angle decomposition.
//          For an open-water thrust T_OW at advance ratio J, the
//          resolved longitudinal and lateral force components at
//          steering angle theta are (T_x, T_y) = T_OW (cos theta,
//          sin theta). A wake-fraction correction reduces effective
//          V_a relative to V_ship.
//
// waterjet: Momentum-conservation thrust:
//             T = rho Q (V_j - V_in)
//           with Q the volumetric flow, V_j the jet exit velocity,
//           and V_in the inlet (vessel) velocity. Propulsive
//           efficiency eta_jet = 2 V_in / (V_j + V_in).

pub const azipod = @import("azipod.zig");
pub const waterjet = @import("waterjet.zig");

test {
    _ = azipod;
    _ = waterjet;
}
