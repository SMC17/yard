//! Segmented Monte Carlo sail passage.
//!
//! Weather is redrawn every `segment_nm` (default 500 nm): true wind speed
//! from the leg's Weibull, true wind angle uniform in the leg's band. The
//! ship sails the course-made-good optimum for each draw (physics.zig);
//! storms above the leg threshold trigger Bernoulli loss draws. One PRNG
//! seeded from the mission base seed (or a holdout override) drives all
//! draws in run-major order — byte-deterministic.
//!
//! Speeds come from a precomputed polar grid (bilinear in TWS x TWA), so
//! the per-draw cost is a table walk, not a physics solve.

const std = @import("std");
const routing = @import("yard_routing");
const sailaero = @import("yard_sailaero");
const seastate = @import("yard_seastate");
const spec = @import("spec.zig");
const physics = @import("physics.zig");

pub const Error = error{ OutOfMemory, RouteInvalid };

const tws_steps: usize = 51;
const tws_max: f64 = 25.0;
const twa_steps: usize = 91; // 0..180 step 2

pub const SpeedGrid = struct {
    /// speed[tws_i][twa_j] through the water on that wind angle [m/s].
    speed: [tws_steps][twa_steps]f64,

    pub fn build(
        kind: sailaero.polar.RigKind,
        plane: sailaero.polar.Hull,
        table: []const sailaero.polar.ResistancePoint,
    ) SpeedGrid {
        var g: SpeedGrid = undefined;
        for (0..tws_steps) |i| {
            const tws = tws_max * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(tws_steps - 1));
            for (0..twa_steps) |j| {
                const twa = 180.0 * @as(f64, @floatFromInt(j)) / @as(f64, @floatFromInt(twa_steps - 1));
                g.speed[i][j] = sailaero.polar.speedAt(kind, plane, tws, twa, table);
            }
        }
        return g;
    }

    pub fn at(self: *const SpeedGrid, tws: f64, twa: f64) f64 {
        const ti = @min(@max(tws, 0.0), tws_max) / tws_max * @as(f64, @floatFromInt(tws_steps - 1));
        const tj = @min(@max(twa, 0.0), 180.0) / 180.0 * @as(f64, @floatFromInt(twa_steps - 1));
        const ia: usize = @intFromFloat(@floor(ti));
        const ja: usize = @intFromFloat(@floor(tj));
        const ib = @min(ia + 1, tws_steps - 1);
        const jb = @min(ja + 1, twa_steps - 1);
        const fi = ti - @floor(ti);
        const fj = tj - @floor(tj);
        const a = self.speed[ia][ja] * (1 - fj) + self.speed[ia][jb] * fj;
        const b = self.speed[ib][ja] * (1 - fj) + self.speed[ib][jb] * fj;
        return a * (1 - fi) + b * fi;
    }

    /// Course-made-good over heading offsets, from the grid.
    pub fn madeGood(self: *const SpeedGrid, tws: f64, twa: f64) f64 {
        var best: f64 = 0;
        var theta: f64 = -88.0;
        while (theta <= 88.0) : (theta += 2.0) {
            const wa = @min(@abs(twa - theta), 180.0);
            const p = self.at(tws, wa) * @cos(std.math.degreesToRadians(theta));
            if (p > best) best = p;
        }
        return best;
    }
};

pub const Aggregate = struct {
    runs: u32,
    losses: u32,
    loss_rate: f64,
    passage_days: f64,
    p95_days: f64,
    route_nm: f64,
    mean_speed_kn: f64,
    base_seed: u64,
};

fn weibullDraw(u: f64, k: f64, lambda: f64) f64 {
    const uu = @min(u, 0.999999);
    return lambda * std.math.pow(f64, -@log(1.0 - uu), 1.0 / k);
}

pub fn simulate(
    allocator: std.mem.Allocator,
    mission: spec.MissionSpec,
    sub: spec.Submission,
    seed_override: ?u64,
) Error!Aggregate {
    const table = physics.resistanceTable(sub.hull);
    const kind = physics.rigKind(sub.rig);
    const plane = sailaero.polar.Hull{ .draft_m = sub.hull.draft_m };
    const grid = SpeedGrid.build(kind, plane, &table);

    const n_legs = mission.waypoints.len - 1;
    var leg_nm = try allocator.alloc(f64, n_legs);
    defer allocator.free(leg_nm);
    var route_nm: f64 = 0;
    for (0..n_legs) |i| {
        const a = mission.waypoints[i];
        const b = mission.waypoints[i + 1];
        const d = routing.great_circle.haversineDistanceM(
            std.math.degreesToRadians(a.lat_deg),
            std.math.degreesToRadians(a.lon_deg),
            std.math.degreesToRadians(b.lat_deg),
            std.math.degreesToRadians(b.lon_deg),
            routing.earth_radius_m,
        ) catch return Error.RouteInvalid;
        leg_nm[i] = d / routing.nautical_mile_m;
        route_nm += leg_nm[i];
    }

    const runs = mission.monte_carlo.runs;
    var days = try allocator.alloc(f64, runs);
    defer allocator.free(days);

    const seed = seed_override orelse mission.monte_carlo.base_seed;
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var losses: u32 = 0;
    var survived: u32 = 0;
    var sum_days: f64 = 0;

    var r: u32 = 0;
    while (r < runs) : (r += 1) {
        var lost = false;
        var hours: f64 = 0;
        legs: for (mission.legs, 0..) |leg, li| {
            const n_seg: usize = @intFromFloat(@ceil(leg_nm[li] / mission.segment_nm));
            const seg_nm = leg_nm[li] / @as(f64, @floatFromInt(n_seg));
            for (0..n_seg) |_| {
                const tws = weibullDraw(random.float(f64), leg.tws_weibull_k, leg.tws_weibull_lambda_mps);
                const twa = leg.twa_min_deg + random.float(f64) * (leg.twa_max_deg - leg.twa_min_deg);
                if (tws > leg.storm_tws_mps and random.float(f64) < leg.storm_loss_prob) {
                    lost = true;
                    break :legs;
                }
                // Wind-driven sea: PM fully developed Hs (upper envelope,
                // documented), direction-weighted drag — head seas take the
                // full 0.02 Hs^2 proxy, beam 0.6x, following seas 0.25x
                // (long-crested swell astern barely slows a driven ship).
                const hs = seastate.pmSignificantHeight(tws);
                const dir_w: f64 = if (twa < 60.0) 1.0 else if (twa < 120.0) 0.6 else 0.25;
                const wave_loss = @min(0.5, 0.02 * hs * hs * dir_w);
                const v = @max(grid.madeGood(tws, twa) * (1.0 - wave_loss), mission.becalmed_floor_mps);
                hours += seg_nm * routing.nautical_mile_m / v / 3600.0;
            }
        }
        if (lost) {
            losses += 1;
            days[r] = std.math.inf(f64);
        } else {
            const d = hours / 24.0;
            days[r] = d;
            sum_days += d;
            survived += 1;
        }
    }

    if (survived == 0) {
        return .{
            .runs = runs,
            .losses = losses,
            .loss_rate = 1.0,
            .passage_days = std.math.inf(f64),
            .p95_days = std.math.inf(f64),
            .route_nm = route_nm,
            .mean_speed_kn = 0,
            .base_seed = seed,
        };
    }

    std.mem.sort(f64, days, {}, std.sort.asc(f64));
    const p95_idx = @min(days.len - 1, (@as(usize, survived) * 95 + 99) / 100);
    const survived_f: f64 = @floatFromInt(survived);
    const mean_days = sum_days / survived_f;

    return .{
        .runs = runs,
        .losses = losses,
        .loss_rate = @as(f64, @floatFromInt(losses)) / @as(f64, @floatFromInt(runs)),
        .passage_days = mean_days,
        .p95_days = days[p95_idx],
        .route_nm = route_nm,
        .mean_speed_kn = route_nm / (mean_days * 24.0),
        .base_seed = seed,
    };
}

const fixtures = @import("fixtures.zig");

fn fixturePair(a: std.mem.Allocator) !struct { m: std.json.Parsed(spec.MissionSpec), s: std.json.Parsed(spec.Submission) } {
    return .{
        .m = try spec.parseMission(a, fixtures.tea_race_mission_json),
        .s = try spec.parseSubmission(a, fixtures.cutty_sark_json),
    };
}

test "route length matches the historical tea route" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixturePair(arena.allocator());
    var total: f64 = 0;
    const wps = f.m.value.waypoints;
    for (1..wps.len) |i| {
        const d = try routing.great_circle.haversineDistanceM(
            std.math.degreesToRadians(wps[i - 1].lat_deg),
            std.math.degreesToRadians(wps[i - 1].lon_deg),
            std.math.degreesToRadians(wps[i].lat_deg),
            std.math.degreesToRadians(wps[i].lon_deg),
            routing.earth_radius_m,
        );
        total += d / routing.nautical_mile_m;
    }
    // Shanghai->London via Sunda and the Cape: ~13,000-15,000 nm.
    try std.testing.expect(total > 12_500 and total < 15_500);
}

test "grid made-good agrees with the direct physics solve" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixturePair(arena.allocator());
    const table = physics.resistanceTable(f.s.value.hull);
    const kind = physics.rigKind(f.s.value.rig);
    const plane = sailaero.polar.Hull{ .draft_m = f.s.value.hull.draft_m };
    const grid = SpeedGrid.build(kind, plane, &table);
    for ([_]f64{ 6.0, 10.0 }) |tws| {
        for ([_]f64{ 45.0, 110.0, 160.0 }) |twa| {
            const direct = physics.madeGoodSpeed(kind, plane, tws, twa, &table);
            const gridded = grid.madeGood(tws, twa);
            try std.testing.expectApproxEqAbs(direct, gridded, 0.35);
        }
    }
}

test "Cutty Sark passage lands in the historical band and is deterministic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixturePair(a);
    const agg1 = try simulate(a, f.m.value, f.s.value, null);
    const agg2 = try simulate(a, f.m.value, f.s.value, null);
    try std.testing.expectEqual(agg1.passage_days, agg2.passage_days);
    try std.testing.expectEqual(agg1.losses, agg2.losses);
    // Pre-registered falsifier band: 85-140 days Shanghai->London.
    try std.testing.expect(agg1.passage_days > 85.0 and agg1.passage_days < 140.0);
    try std.testing.expect(agg1.loss_rate < 0.15);
}

test "the clipper beats the portly Indiaman" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixturePair(a);
    const indiaman = try spec.parseSubmission(a, fixtures.indiaman_json);
    const clipper = try simulate(a, f.m.value, f.s.value, null);
    const trader = try simulate(a, f.m.value, indiaman.value, null);
    try std.testing.expect(trader.passage_days > clipper.passage_days + 10.0);
}

test "seed override changes draws but stays deterministic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixturePair(a);
    const pub_run = try simulate(a, f.m.value, f.s.value, null);
    const holdout1 = try simulate(a, f.m.value, f.s.value, 0xD00D);
    const holdout2 = try simulate(a, f.m.value, f.s.value, 0xD00D);
    try std.testing.expectEqual(holdout1.passage_days, holdout2.passage_days);
    try std.testing.expect(holdout1.passage_days != pub_run.passage_days);
    // Same physics, different weather draws: means stay in the same regime.
    try std.testing.expect(@abs(holdout1.passage_days - pub_run.passage_days) < 20.0);
}
