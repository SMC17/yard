//! Pareto front SVG export for spiral optimization campaigns.

const std = @import("std");
const spiral = @import("yard_spiral");
const viz = @import("yard_viz");
const naval = @import("yard_naval_arch");

pub const Error = error{
    OutOfMemory,
    StageFailed,
    OutsideValidityEnvelope,
    ConvergenceFailed,
    SimilarityFailed,
    SimulationFailed,
    NoPoints,
};

pub fn renderSvg(
    allocator: std.mem.Allocator,
    front: []const spiral.optimizer.ParetoPoint,
) Error![]u8 {
    var viz_pts = try allocator.alloc(viz.pareto_svg.Point, front.len);
    defer allocator.free(viz_pts);
    var indices = try allocator.alloc(usize, front.len);
    defer allocator.free(indices);

    for (front, 0..) |p, i| {
        viz_pts[i] = .{
            .power_kw = p.power_kw,
            .heave_m = p.heave_m,
            .gm_m = p.gm_m,
        };
        indices[i] = i;
    }

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    viz.pareto_svg.render(&list, allocator, .{
        .points = viz_pts,
        .front_indices = indices,
        .style = .{ .title = "Yard Spiral — Pareto Front" },
    }) catch |err| switch (err) {
        error.NoPoints => return Error.NoPoints,
        error.OutOfMemory => return Error.OutOfMemory,
    };
    return list.toOwnedSlice(allocator);
}

pub const CampaignResult = struct {
    front: []spiral.optimizer.ParetoPoint,
    svg: []u8,
    proof_level: naval.ProofLevel = .unit_tested,

    pub fn deinit(self: CampaignResult, allocator: std.mem.Allocator) void {
        allocator.free(self.front);
        allocator.free(self.svg);
    }
};

pub fn runCampaign(
    allocator: std.mem.Allocator,
    population: u32,
    generations: u32,
    gm_min: f64,
) Error!CampaignResult {
    const orch = spiral.orchestrator.Orchestrator.init(allocator, 1, .mid);
    const front = spiral.optimizer.gaParetoExplore(orch, population, generations, gm_min) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.StageFailed,
    };
    const svg = try renderSvg(allocator, front);
    return .{ .front = front, .svg = svg };
}

test "pareto campaign produces svg" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var campaign = try runCampaign(arena.allocator(), 4, 1, 0.5);
    defer campaign.deinit(arena.allocator());
    try std.testing.expect(campaign.svg.len > 100);
    try std.testing.expect(std.mem.indexOf(u8, campaign.svg, "<svg") != null);
}