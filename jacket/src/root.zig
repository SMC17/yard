// yard-jacket-zig public API.
//
// morison: Morison-equation wave-load per unit length on a circular
//          jacket member (typically a chord, brace, or pile). Per
//          unit length, normal to the member axis:
//            f = 0.5 rho C_D D u|u| + rho C_M (pi D^2 / 4) du/dt
//          where u is the projected normal water-particle velocity at
//          the member. Linear-wave kinematics for u and du/dt are
//          provided as helper functions in the airy submodule.

pub const morison = @import("morison.zig");
pub const airy = @import("airy.zig");

test {
    _ = morison;
    _ = airy;
}
