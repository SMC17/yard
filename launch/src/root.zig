// yard-launch-zig public API.
//
// end_launch: End-launch (stern-first slipway) energy balance. The
//             ship accelerates down the ways under gravity and is
//             retarded by sliding friction:
//               m a = m g sin(alpha) - mu m g cos(alpha)
//             with alpha the slipway declivity and mu the kinetic
//             friction coefficient. Way-end velocity follows from
//             energy balance.
//
// pivoting:   Pivoting check at the stern lift-off. As the ship
//             enters the water, the stern lifts off the cradle when
//             buoyancy exceeds remaining cradle reaction. The pivot
//             moment about the forward cradle balances the bow weight.
//
// side_launch: Side-launch kinematics. A ship launched broadside
//              from a low slipway tips into the water at maximum
//              heel angle phi_max determined by the slipway height
//              and the ship's metacentric stability.

pub const end_launch = @import("end_launch.zig");
pub const pivoting = @import("pivoting.zig");
pub const side_launch = @import("side_launch.zig");

test {
    _ = end_launch;
    _ = pivoting;
    _ = side_launch;
}
