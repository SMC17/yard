// yard-drydock-zig public API.
//
// blocks:  Drydock block-plan reaction distribution. Total ship
//          weight is distributed across the keel + bilge blocks.
//          Per-block reaction depends on the longitudinal weight
//          distribution; for a uniform block plan the average
//          per-block reaction = W / N.
//
// pressure: Keel-block bearing pressure check. Block area in contact
//           with the keel must satisfy:
//             p = R / A < p_allow
//           with p_allow ~ 5 MPa for hardwood (Douglas Fir), 2 MPa
//           for softwood, 50 MPa for steel.
//
// transverse: Transverse stability of the docking vessel. As the
//             water drops, the ship sits on the blocks; transverse
//             stability is reduced. The reserve metacentric height
//             GM_residual must remain positive at the docking water
//             level.

pub const blocks = @import("blocks.zig");
pub const pressure = @import("pressure.zig");
pub const transverse = @import("transverse.zig");

test {
    _ = blocks;
    _ = pressure;
    _ = transverse;
}
