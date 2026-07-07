// yard-coupled-motions-zig public API.
//
// coupled: 3-DOF coupled heave-pitch-roll RAO solver in the frequency
//          domain. Solves [-(M + A)omega^2 + i B omega + C] X = F for a
//          complex 3-vector X given mass, added-mass, damping, restoring
//          and forcing matrices. When the matrices are block-diagonal,
//          the 3-DOF system decouples to three independent 1-DOF RAOs
//          matching yard-strip-theory's heave amplitude.

pub const coupled = @import("coupled.zig");

test {
    _ = coupled;
}
