// yard-hydro-zig public API.
//
// Three modules:
//   simpson    composite Simpson 1/3 and 3/8 quadrature on ordinate arrays
//   wigley     parametric Wigley hull, half-breadth y(x, z), closed-form integrals
//   box_barge  rectangular barge, all hydrostatic quantities closed-form
//   integrate  hydrostatic integrators consuming ordinate / offsets tables

pub const simpson = @import("simpson.zig");
pub const wigley = @import("wigley.zig");
pub const box_barge = @import("box_barge.zig");
pub const integrate = @import("integrate.zig");

test {
    _ = simpson;
    _ = wigley;
    _ = box_barge;
    _ = integrate;
}
