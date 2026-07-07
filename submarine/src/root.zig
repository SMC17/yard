// yard-submarine-zig public API.
//
// pressure_hull: Pressure-hull collapse depth via von Mises buckling
//                of a cylindrical shell + Bryant ring-stiffened
//                interframe yield + crush-depth safety factor.
//
// dive:          Hydrostatic dive equation: density + depth + ballast
//                trim. Vertical equilibrium = W - B = 0; positive
//                buoyancy gives positive ascent rate.
//
// ballast:       Main-ballast-tank (MBT) volume from displacement
//                surfaced vs submerged + trim-and-list tank model.

pub const pressure_hull = @import("pressure_hull.zig");
pub const dive = @import("dive.zig");
pub const ballast = @import("ballast.zig");

test {
    _ = pressure_hull;
    _ = dive;
    _ = ballast;
}
