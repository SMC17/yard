// yard-fossen-6dof-zig public API.
//
// fossen: Linearized 6-DOF marine craft state space per Fossen 2011
//         Handbook of Marine Craft Hydrodynamics and Motion Control,
//         with an RK4 integrator. The full nonlinear C(nu) and D(nu)
//         are out of scope for v0.0.0; M is diagonal and constant,
//         linear damping d_lin only, restoring g(eta) is linear in
//         (heave, roll, pitch).

pub const fossen = @import("fossen.zig");

test {
    _ = fossen;
}
