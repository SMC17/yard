const std = @import("std");

pub const Error = error{
    NonPositiveDuration,
    UnknownActivity,
    EmptyNetwork,
    InvalidEdge,
    BufferTooSmall,
};

/// Activity record: index serves as the activity ID.
pub const Activity = struct {
    duration_days: f64,
};

/// Precedence edge: activity `to` cannot start until `from` finishes.
pub const Edge = struct {
    from: usize,
    to: usize,
};

pub const Schedule = struct {
    es: []f64, // earliest start
    ef: []f64, // earliest finish
    ls: []f64, // latest start
    lf: []f64, // latest finish
    tf: []f64, // total float = LS - ES
};

/// Forward pass: compute earliest start / finish for each activity.
/// `topo_order` must be a topological ordering (predecessors before
/// successors). Buffers `es` / `ef` must have length >= activities.len.
pub fn forwardPass(
    activities: []const Activity,
    edges: []const Edge,
    topo_order: []const usize,
    es: []f64,
    ef: []f64,
) Error!void {
    if (activities.len == 0) return Error.EmptyNetwork;
    if (es.len < activities.len or ef.len < activities.len) return Error.BufferTooSmall;
    if (topo_order.len != activities.len) return Error.InvalidEdge;
    for (activities, 0..) |a, i| {
        if (!(a.duration_days >= 0)) return Error.NonPositiveDuration;
        es[i] = 0.0;
        ef[i] = a.duration_days;
    }
    for (topo_order) |id| {
        if (id >= activities.len) return Error.UnknownActivity;
        for (edges) |e| {
            if (e.to == id) {
                if (e.from >= activities.len) return Error.InvalidEdge;
                if (ef[e.from] > es[id]) es[id] = ef[e.from];
            }
        }
        ef[id] = es[id] + activities[id].duration_days;
    }
}

/// Project finish: max(EF) across all activities.
pub fn projectFinish(ef: []const f64) f64 {
    var max: f64 = 0.0;
    for (ef) |v| if (v > max) {
        max = v;
    };
    return max;
}

/// Backward pass: given a project finish T_finish, compute latest
/// finish / start such that LF for an activity is T_finish unless
/// the activity has successors, in which case LF = min(LS over
/// successors).
pub fn backwardPass(
    activities: []const Activity,
    edges: []const Edge,
    topo_order: []const usize,
    T_finish: f64,
    ls: []f64,
    lf: []f64,
) Error!void {
    if (activities.len == 0) return Error.EmptyNetwork;
    if (ls.len < activities.len or lf.len < activities.len) return Error.BufferTooSmall;
    for (activities, 0..) |a, i| {
        _ = a;
        lf[i] = T_finish;
        ls[i] = T_finish;
    }
    var ri: usize = topo_order.len;
    while (ri > 0) {
        ri -= 1;
        const id = topo_order[ri];
        if (id >= activities.len) return Error.UnknownActivity;
        var min_ls: f64 = T_finish;
        var has_successor: bool = false;
        for (edges) |e| {
            if (e.from == id) {
                has_successor = true;
                if (ls[e.to] < min_ls) min_ls = ls[e.to];
            }
        }
        if (has_successor) lf[id] = min_ls;
        ls[id] = lf[id] - activities[id].duration_days;
    }
}

/// Total float per activity: LS - ES. Critical activities have
/// float == 0.
pub fn totalFloat(
    es: []const f64,
    ls: []const f64,
    tf: []f64,
) Error!void {
    if (es.len != ls.len) return Error.InvalidEdge;
    if (tf.len < es.len) return Error.BufferTooSmall;
    for (es, 0..) |s, i| {
        tf[i] = ls[i] - s;
    }
}

test "single-activity network: project finish equals duration" {
    const acts = [_]Activity{.{ .duration_days = 5.0 }};
    const edges: []const Edge = &[_]Edge{};
    const topo = [_]usize{0};
    var es: [1]f64 = undefined;
    var ef: [1]f64 = undefined;
    try forwardPass(&acts, edges, &topo, &es, &ef);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), es[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), ef[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), projectFinish(&ef), 1e-12);
}

test "linear chain A -> B -> C" {
    const acts = [_]Activity{
        .{ .duration_days = 3.0 },
        .{ .duration_days = 4.0 },
        .{ .duration_days = 2.0 },
    };
    const edges = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 2 } };
    const topo = [_]usize{ 0, 1, 2 };
    var es: [3]f64 = undefined;
    var ef: [3]f64 = undefined;
    try forwardPass(&acts, &edges, &topo, &es, &ef);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), es[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), es[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), es[2], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), projectFinish(&ef), 1e-12);
}

test "diamond A -> {B, C} -> D" {
    const acts = [_]Activity{
        .{ .duration_days = 2.0 },
        .{ .duration_days = 5.0 },
        .{ .duration_days = 3.0 },
        .{ .duration_days = 4.0 },
    };
    const edges = [_]Edge{
        .{ .from = 0, .to = 1 },
        .{ .from = 0, .to = 2 },
        .{ .from = 1, .to = 3 },
        .{ .from = 2, .to = 3 },
    };
    const topo = [_]usize{ 0, 1, 2, 3 };
    var es: [4]f64 = undefined;
    var ef: [4]f64 = undefined;
    try forwardPass(&acts, &edges, &topo, &es, &ef);
    // D starts after the slower of B (2+5=7) or C (2+3=5), so ES_D = 7.
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), es[3], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 11.0), projectFinish(&ef), 1e-12);
}

test "backward pass on linear chain leaves zero float" {
    const acts = [_]Activity{
        .{ .duration_days = 3.0 },
        .{ .duration_days = 4.0 },
        .{ .duration_days = 2.0 },
    };
    const edges = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 2 } };
    const topo = [_]usize{ 0, 1, 2 };
    var es: [3]f64 = undefined;
    var ef: [3]f64 = undefined;
    try forwardPass(&acts, &edges, &topo, &es, &ef);
    const T = projectFinish(&ef);
    var ls: [3]f64 = undefined;
    var lf: [3]f64 = undefined;
    try backwardPass(&acts, &edges, &topo, T, &ls, &lf);
    var tf: [3]f64 = undefined;
    try totalFloat(&es, &ls, &tf);
    inline for (0..3) |i| {
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), tf[i], 1e-12);
    }
}

test "diamond: C has positive float" {
    const acts = [_]Activity{
        .{ .duration_days = 2.0 },
        .{ .duration_days = 5.0 },
        .{ .duration_days = 3.0 },
        .{ .duration_days = 4.0 },
    };
    const edges = [_]Edge{
        .{ .from = 0, .to = 1 },
        .{ .from = 0, .to = 2 },
        .{ .from = 1, .to = 3 },
        .{ .from = 2, .to = 3 },
    };
    const topo = [_]usize{ 0, 1, 2, 3 };
    var es: [4]f64 = undefined;
    var ef: [4]f64 = undefined;
    try forwardPass(&acts, &edges, &topo, &es, &ef);
    const T = projectFinish(&ef);
    var ls: [4]f64 = undefined;
    var lf: [4]f64 = undefined;
    try backwardPass(&acts, &edges, &topo, T, &ls, &lf);
    var tf: [4]f64 = undefined;
    try totalFloat(&es, &ls, &tf);
    // A, B, D are critical (zero float). C has 2 days of float.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), tf[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), tf[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), tf[2], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), tf[3], 1e-12);
}

test "empty network rejected" {
    const acts: []const Activity = &[_]Activity{};
    const edges: []const Edge = &[_]Edge{};
    const topo: []const usize = &[_]usize{};
    var es: [0]f64 = undefined;
    var ef: [0]f64 = undefined;
    try std.testing.expectError(Error.EmptyNetwork, forwardPass(acts, edges, topo, &es, &ef));
}

test "negative duration rejected" {
    const acts = [_]Activity{.{ .duration_days = -1.0 }};
    const edges: []const Edge = &[_]Edge{};
    const topo = [_]usize{0};
    var es: [1]f64 = undefined;
    var ef: [1]f64 = undefined;
    try std.testing.expectError(Error.NonPositiveDuration, forwardPass(&acts, edges, &topo, &es, &ef));
}
