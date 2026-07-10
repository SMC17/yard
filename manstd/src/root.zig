//! yard-manstd — IMO ship manoeuvrability standards + Nomoto prediction.
//!
//! Criteria are IMO Resolution MSC.137(76) "Standards for Ship
//! Manoeuvrability" (2002), applied at full load, even keel, >=90% of the
//! speed corresponding to 85% MCR. The zig-zag overshoot limits depend on
//! L/V [s], piecewise-linear between the resolution's breakpoints.
//! Prediction uses the first-order Nomoto model T r' + r = K delta —
//! the standard preliminary-design surrogate for the IMO trials.
//!
//! Proof level: unit-tested (resolution numbers exact; Nomoto integrator
//! property-tested).

pub const criteria = @import("criteria.zig");
pub const nomoto = @import("nomoto.zig");

test {
    _ = criteria;
    _ = nomoto;
}
