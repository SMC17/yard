//! yard-benchmark — standard-hull validation harness for the naval sim suite.

pub const hulls = @import("hulls.zig");
pub const harness = @import("harness.zig");

test {
    _ = hulls;
    _ = harness;
}