// yard-dynpos-zig public API.
//
// allocation: Dynamic-positioning thruster allocation for a 3-DOF
//             surge / sway / yaw demand vector. Given N fixed-
//             direction thrusters with thrust direction (alpha_i)
//             relative to the body x-axis and arm vector (x_i, y_i)
//             from the centre of rotation, the configuration matrix
//             B [3 x N] maps the thrust column u to the body-force
//             vector tau:
//               tau = B u
//             The minimum-energy allocation solves the underdetermined
//             system via the pseudo-inverse:
//               u = B^T (B B^T)^(-1) tau.
//             This kernel exposes the 3-thruster case in closed form
//             plus a general N x 3 pseudo-inverse for N <= 8.

pub const allocation = @import("allocation.zig");

test {
    _ = allocation;
}
