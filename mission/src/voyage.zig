//! Seeded Monte Carlo voyage simulation over great-circle route legs.
//!
//! v0 model, every assumption explicit:
//!   - Attainable calm-water speed: bisection on Holtrop-Mennen required power
//!     vs installed power x service fraction x propulsive efficiency.
//!   - Per-leg significant wave height: Weibull draw (inverse CDF).
//!   - Weather speed loss: v_eff = v x (1 - min(0.5, 0.02 Hs^2)) — a documented
//!     v0 proxy; replaced by rao-spectrum added-resistance coupling later.
//!   - Storm loss: Hs above the mission storm threshold triggers a Bernoulli
//!     loss draw. Lost runs deliver no cargo.
//! Deterministic competition missions use Yard Arena's `blake3-counter-v1`:
//! weather and damage are independent random-access streams. Early v0 mission
//! files without `rng_algorithm` retain `zig-default-prng-v0` compatibility.

const std = @import("std");
const routing = @import("yard_routing");
const cargo_resistance = @import("yard_cargo_resistance");
const arena_rng = @import("yard_arena_rng");
const spec = @import("spec.zig");
const gates = @import("gates.zig");

pub const Error = error{
    OutOfMemory,
    RouteInvalid,
    ResistanceFailed,
    InsufficientPower,
    InvalidRngAlgorithm,
};

pub const Aggregate = struct {
    runs: u32,
    losses: u32,
    loss_rate: f64,
    /// Mean voyage duration over surviving runs [days].
    mean_days: f64,
    /// 95th percentile voyage duration over surviving runs [days].
    p95_days: f64,
    /// Cargo delivered averaged over ALL runs (lost runs deliver zero) [t].
    cargo_delivered_t: f64,
    /// Mean propulsive energy per delivered tonne over surviving runs [kWh/t].
    transport_cost_index: f64,
    /// Attainable calm-water speed [m/s].
    calm_speed_mps: f64,
    route_nm: f64,
};

/// Solve attainable calm-water speed: R_T(v) * v / eta_D = P_available.
pub fn calmWaterSpeed(sub: spec.Submission) Error!f64 {
    const hull = gates.holtropParticulars(sub.hull);
    const p_avail_w = sub.propulsion.installed_kw * 1000.0 *
        sub.propulsion.service_fraction * sub.propulsion.propulsive_efficiency;
    if (p_avail_w <= 0) return Error.InsufficientPower;

    const required = struct {
        fn power(h: @TypeOf(hull), v: f64) Error!f64 {
            const out = cargo_resistance.evaluate(.{ .hull = h, .speed_mps = v }) catch
                return Error.ResistanceFailed;
            return out.r_total * v;
        }
    }.power;

    var lo: f64 = 0.5;
    var hi: f64 = 15.0;
    if (try required(hull, lo) > p_avail_w) return Error.InsufficientPower;
    // Expand hi only if the hull can absorb it (Holtrop stays valid; speed
    // only enters through Fn/Rn so evaluate cannot reject on speed).
    while (try required(hull, hi) < p_avail_w and hi < 30.0) hi += 5.0;

    var i: usize = 0;
    while (i < 60) : (i += 1) {
        const mid = 0.5 * (lo + hi);
        if (try required(hull, mid) > p_avail_w) {
            hi = mid;
        } else {
            lo = mid;
        }
    }
    return 0.5 * (lo + hi);
}

pub fn routeDistanceM(waypoints: []const spec.Waypoint) Error!f64 {
    if (waypoints.len < 2) return Error.RouteInvalid;
    var total: f64 = 0;
    var i: usize = 1;
    while (i < waypoints.len) : (i += 1) {
        const a = waypoints[i - 1];
        const b = waypoints[i];
        total += routing.great_circle.haversineDistanceM(
            std.math.degreesToRadians(a.lat_deg),
            std.math.degreesToRadians(a.lon_deg),
            std.math.degreesToRadians(b.lat_deg),
            std.math.degreesToRadians(b.lon_deg),
            routing.earth_radius_m,
        ) catch return Error.RouteInvalid;
    }
    return total;
}

fn weibullDraw(u: f64, k: f64, lambda: f64) f64 {
    // Inverse CDF; u in [0,1). Clamp to avoid ln(0).
    const uu = @min(u, 0.999999);
    return lambda * std.math.pow(f64, -@log(1.0 - uu), 1.0 / k);
}

pub fn simulate(allocator: std.mem.Allocator, mission: spec.MissionSpec, sub: spec.Submission) Error!Aggregate {
    const calm_v = try calmWaterSpeed(sub);
    if (calm_v < mission.gates.min_calm_speed_mps) return Error.InsufficientPower;

    const n_legs = mission.waypoints.len - 1;
    if (mission.waypoints.len < 2) return Error.RouteInvalid;
    var leg_dists = try allocator.alloc(f64, n_legs);
    defer allocator.free(leg_dists);
    var total_m: f64 = 0;
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
        leg_dists[i] = d;
        total_m += d;
    }

    const runs = mission.monte_carlo.runs;
    var days = try allocator.alloc(f64, runs);
    defer allocator.free(days);

    const stable_rng = std.mem.eql(u8, mission.monte_carlo.rng_algorithm, arena_rng.algorithm_id);
    const legacy_rng = std.mem.eql(u8, mission.monte_carlo.rng_algorithm, "zig-default-prng-v0");
    if (!stable_rng and !legacy_rng) return Error.InvalidRngAlgorithm;
    var prng = std.Random.DefaultPrng.init(mission.monte_carlo.base_seed);
    const random = prng.random();

    const env = mission.environment;
    const p_shaft_kw = sub.propulsion.installed_kw * sub.propulsion.service_fraction;

    var losses: u32 = 0;
    var survived: u32 = 0;
    var sum_days: f64 = 0;
    var sum_energy_kwh: f64 = 0;

    var r: u32 = 0;
    while (r < runs) : (r += 1) {
        var lost = false;
        var hours: f64 = 0;
        for (leg_dists, 0..) |dist_m, leg_index| {
            const draw_index = (@as(u64, r) << 32) | @as(u64, @intCast(leg_index));
            const weather_u = if (stable_rng)
                arena_rng.drawUnitF64(mission.monte_carlo.base_seed, 0, draw_index)
            else
                random.float(f64);
            const hs = weibullDraw(weather_u, env.hs_weibull_k, env.hs_weibull_lambda_m);
            if (hs > env.storm_hs_m) {
                const damage_u = if (stable_rng)
                    arena_rng.drawUnitF64(mission.monte_carlo.base_seed, 2, draw_index)
                else
                    random.float(f64);
                if (damage_u < env.storm_loss_prob) {
                    lost = true;
                    break;
                }
            }
            const loss_frac = @min(0.5, 0.02 * hs * hs);
            const v_eff = calm_v * (1.0 - loss_frac);
            hours += (dist_m / v_eff) / 3600.0;
        }
        if (lost) {
            losses += 1;
            days[r] = std.math.inf(f64);
        } else {
            const d = hours / 24.0;
            days[r] = d;
            sum_days += d;
            sum_energy_kwh += p_shaft_kw * hours;
            survived += 1;
        }
    }

    if (survived == 0) {
        return .{
            .runs = runs,
            .losses = losses,
            .loss_rate = 1.0,
            .mean_days = std.math.inf(f64),
            .p95_days = std.math.inf(f64),
            .cargo_delivered_t = 0,
            .transport_cost_index = std.math.inf(f64),
            .calm_speed_mps = calm_v,
            .route_nm = total_m / routing.nautical_mile_m,
        };
    }

    std.mem.sort(f64, days, {}, std.sort.asc(f64));
    const p95_idx = @min(days.len - 1, (@as(usize, survived) * 95 + 99) / 100);
    const runs_f: f64 = @floatFromInt(runs);
    const survived_f: f64 = @floatFromInt(survived);

    const delivered_mean = sub.loading.cargo_t * survived_f / runs_f;
    const energy_per_run = sum_energy_kwh / survived_f;

    return .{
        .runs = runs,
        .losses = losses,
        .loss_rate = @as(f64, @floatFromInt(losses)) / runs_f,
        .mean_days = sum_days / survived_f,
        .p95_days = days[p95_idx],
        .cargo_delivered_t = delivered_mean,
        .transport_cost_index = energy_per_run / sub.loading.cargo_t,
        .calm_speed_mps = calm_v,
        .route_nm = total_m / routing.nautical_mile_m,
    };
}

fn testFixtures(a: std.mem.Allocator) !struct { m: std.json.Parsed(spec.MissionSpec), s: std.json.Parsed(spec.Submission) } {
    return .{
        .m = try spec.parseMission(a, spec.test_mission_json),
        .s = try spec.parseSubmission(a, spec.test_submission_json),
    };
}

test "calm-water speed is physical for the baseline coaster" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try testFixtures(arena.allocator());
    const v = try calmWaterSpeed(f.s.value);
    // 4 MW coaster: cruising speed must land in a plausible 4-9 m/s band.
    try std.testing.expect(v > 4.0 and v < 9.0);
}

test "simulate is deterministic for identical inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try testFixtures(a);
    const first = try simulate(a, f.m.value, f.s.value);
    const second = try simulate(a, f.m.value, f.s.value);
    try std.testing.expectEqual(first.mean_days, second.mean_days);
    try std.testing.expectEqual(first.p95_days, second.p95_days);
    try std.testing.expectEqual(first.losses, second.losses);
    try std.testing.expectEqual(first.transport_cost_index, second.transport_cost_index);
}

test "stable voyage RNG keeps weather and damage streams independent" {
    const coordinate: u64 = (@as(u64, 17) << 32) | 4;
    const weather = arena_rng.drawUnitF64(20260710, 0, coordinate);
    const damage = arena_rng.drawUnitF64(20260710, 2, coordinate);
    _ = arena_rng.drawUnitF64(20260710, 0, coordinate + 1);
    try std.testing.expectEqual(damage, arena_rng.drawUnitF64(20260710, 2, coordinate));
    try std.testing.expect(weather != damage);
}

test "unknown RNG algorithm fails closed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try testFixtures(a);
    var mission = f.m.value;
    mission.monte_carlo.rng_algorithm = "unknown";
    try std.testing.expectError(Error.InvalidRngAlgorithm, simulate(a, mission, f.s.value));
}

test "voyage aggregate is physically sane" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try testFixtures(a);
    const agg = try simulate(a, f.m.value, f.s.value);
    // Rotterdam-Immingham round trip is ~400 nm; at 4-9 m/s that is 1-3 days.
    try std.testing.expect(agg.route_nm > 300 and agg.route_nm < 500);
    try std.testing.expect(agg.mean_days > 0.8 and agg.mean_days < 4.0);
    try std.testing.expect(agg.p95_days >= agg.mean_days);
    try std.testing.expect(agg.loss_rate >= 0.0 and agg.loss_rate < 0.2);
    try std.testing.expect(agg.transport_cost_index > 0);
}

test "more installed power shortens the voyage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try testFixtures(a);
    var boosted = f.s.value;
    boosted.propulsion.installed_kw = 8000.0;
    const base = try simulate(a, f.m.value, f.s.value);
    const fast = try simulate(a, f.m.value, boosted);
    try std.testing.expect(fast.calm_speed_mps > base.calm_speed_mps);
    try std.testing.expect(fast.mean_days < base.mean_days);
}

test "underpowered submission is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try testFixtures(a);
    var weak = f.s.value;
    weak.propulsion.installed_kw = 10.0;
    try std.testing.expectError(Error.InsufficientPower, simulate(a, f.m.value, weak));
}
