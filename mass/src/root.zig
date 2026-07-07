// yard-mass-zig public API.
//
// e26: IACS Unified Requirement E26 / E27 cyber-resilience compliance
//      harness. A Computer-Based System (CBS) carries a criticality
//      classification (critical, essential, non-essential); each
//      criticality maps to a set of required controls; each control
//      requires evidence (policy, configuration, test, audit). The
//      harness checks that every applicable control has the required
//      evidence; missing evidence is reported as a gap.

pub const e26 = @import("e26.zig");

test {
    _ = e26;
}
