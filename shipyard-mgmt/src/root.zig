// yard-shipyard-mgmt-zig public API.
//
// cpm:    Critical Path Method. Given a topologically-ordered
//         activity network with durations and precedence edges, the
//         kernel computes earliest start / finish (forward pass),
//         latest start / finish (backward pass), and total float
//         per activity. Critical activities have zero total float.
//
// pert:   PERT three-point estimate. For optimistic / most-likely /
//         pessimistic duration triples (a, m, b):
//           mean = (a + 4 m + b) / 6
//           sigma = (b - a) / 6
//         The project completion-time distribution is approximated
//         as Gaussian with mean = sum of critical-path means and
//         variance = sum of critical-path variances.
//
// resource: Resource-loading histogram. Per-day or per-week
//           resource usage summed across active activities;
//           resource peak load = max over the histogram.

pub const cpm = @import("cpm.zig");
pub const pert = @import("pert.zig");
pub const resource = @import("resource.zig");

test {
    _ = cpm;
    _ = pert;
    _ = resource;
}
