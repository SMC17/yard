// yard-helideck-zig public API.
//
// motion: CAP 437 / IMO MSC.1/Circ.1378 helideck motion envelopes.
//         Accelerations at the deck CG follow from ship-motion
//         angular rates and lever arms; the regulatory envelopes
//         limit pitch, roll, heave-velocity, and inclination.
//         A standard helideck motion-limit table is encoded by class
//         (helicopter category 1-3 per MSC.1/Circ.1054).

pub const motion = @import("motion.zig");

test {
    _ = motion;
}
