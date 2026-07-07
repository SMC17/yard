// yard-springing-zig public API.
//
// hull_girder: Two-node hull-girder vertical-bending natural frequency
//              per Schlick's formula:
//                f_2 = phi sqrt(I / (Delta L^3))
//              with phi a calibrating coefficient (~ 320,000 in SI
//              for typical ship hulls), I the midship moment of
//              inertia [m^4], Delta the displacement [t], and L the
//              ship length [m]. This is the classical first-mode
//              two-node beam-bending whipping / springing frequency.
//
// whipping: Transient decay of a hull-girder whipping response. The
//           bending-moment time history after a slamming impulse
//           follows e^(-zeta omega t) * cos(omega_d t) with zeta the
//           critical-damping ratio (typ. 0.01-0.02 in air).

pub const hull_girder = @import("hull_girder.zig");
pub const whipping = @import("whipping.zig");

test {
    _ = hull_girder;
    _ = whipping;
}
