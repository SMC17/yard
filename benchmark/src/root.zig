//! yard-benchmark — standard-hull validation harness for the naval sim suite.

pub const hulls = @import("hulls.zig");
pub const harness = @import("harness.zig");
pub const tank_data = @import("tank_data.zig");
pub const tank_extrapolate = @import("tank_extrapolate.zig");

test {
    _ = hulls;
    _ = harness;
    _ = tank_data;
    _ = tank_extrapolate;
}