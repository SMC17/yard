// yard-stability-zig public API.
//
// gz:     GZ righting-arm computation: small-angle and wall-sided
//         Atwood. Free-surface correction.
// damage: Lost-buoyancy box-barge damage solver via bisection on the
//         damaged-condition waterline.
// is_code: IMO 2008 Intact Stability Code Part A 2.2 numerical criteria
//         evaluator (GZ-curve integration + threshold checks).
// kn:     KN cross-curves of stability + full GZ-curve reconstruction
//         via `GZ(phi) = KN(phi) - KG sin(phi)` + dynamic stability
//         (Simpson) + range-of-stability zero-crossing.

pub const gz = @import("gz.zig");
pub const damage = @import("damage.zig");
pub const is_code = @import("is_code.zig");
pub const kn = @import("kn.zig");

test {
    _ = gz;
    _ = damage;
    _ = is_code;
    _ = kn;
}
