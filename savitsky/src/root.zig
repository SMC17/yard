// yard-savitsky-zig public API.
//
// savitsky: Savitsky 1964 planing-hull lift prediction. For a prismatic
//           V-bottom planing hull with deadrise angle beta, the lift
//           coefficient at trim angle tau and mean wetted-length-to-
//           beam ratio lambda is:
//             C_L0 = tau^1.1 (0.0120 lambda^0.5 + 0.0055 lambda^2.5 / C_V^2)
//             C_Lbeta = C_L0 - 0.0065 beta C_L0^0.6
//           where C_V = V / sqrt(g B) is the speed coefficient (beam
//           Froude). All inputs in SI; angles in degrees as in the
//           original Savitsky paper.

pub const savitsky = @import("savitsky.zig");

test {
    _ = savitsky;
}
