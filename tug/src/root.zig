// yard-tug-zig public API.
//
// bollard:  Bollard pull regression and operational classifications.
//           For a Z-drive escort tug: BP ~ 1.5 P_brake / V_thrust at
//           low speed. Empirical: BP[kN] ~ 0.12 * P[kW] for modern
//           ASD tugs; 0.10 for conventional twin-screw.
//
// indirect: Indirect-towing (Reverse Arrest) effective force at a
//           tow-line angle theta to the assisted-ship axis:
//             F_eff = BP * sin(beta) * cos(theta)
//           where beta is the tug's heel angle into the water.
//
// effective: Effective bollard pull at the towed ship's speed
//             (Carlton 2018 fit):
//               BP(V) = BP_0 * (1 - V / V_max)
//             where V_max is the maximum bollard speed (typ. 5-7 m/s
//             for an ASD tug).

pub const bollard = @import("bollard.zig");
pub const indirect = @import("indirect.zig");
pub const effective = @import("effective.zig");

test {
    _ = bollard;
    _ = indirect;
    _ = effective;
}
