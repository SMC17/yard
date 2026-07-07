// yard-shaft-zig public API.
//
// holzer: Holzer 1921 torsional-vibration natural-frequency search
//         for a lumped inertia-and-spring shaft system. Given an
//         array of inertias `J_i` and torsional springs `k_i`
//         between station i and i + 1, the Holzer method computes a
//         residual torque T_end(omega) at the free end; natural
//         frequencies are the omega for which T_end = 0.
//
// shaft_stiffness: closed-form torsional stiffness of a uniform
//                  circular shaft segment: k = G J / L where J is
//                  the polar moment of inertia for a solid shaft
//                  pi D^4 / 32 or a hollow shaft pi (D_o^4 - D_i^4)
//                  / 32.

pub const holzer = @import("holzer.zig");
pub const shaft_stiffness = @import("shaft_stiffness.zig");

test {
    _ = holzer;
    _ = shaft_stiffness;
}
