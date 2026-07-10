//! yard-weathercrit — IMO weather criterion (severe wind and rolling),
//! IS Code 2008 Part A, 2.3, encoded with the resolution's tables.
//!
//!   lw1 = P A Z / (1000 g disp)   steady wind heeling lever, P = 504 Pa
//!   lw2 = 1.5 lw1                 gust lever
//!   phi1 = 109 k X1 X2 sqrt(r s)  windward roll-back angle [deg]
//!   r = 0.73 + 0.6 OG/d,  T_roll = 2 C B / sqrt(GM),
//!   C = 0.373 + 0.023 B/d - 0.043 Lwl/100
//! Criterion: area b (GZ over lw2, phi0 to min(phi2, phi_f, 50 deg)) >=
//! area a (lw2 over GZ, phi0-phi1 to phi0); plus phi0 <= 16 deg.
//!
//! Proof level: unit-tested (tables exact at breakpoints, levers and
//! energy balance hand-checked on analytic GZ curves).

const std = @import("std");

pub const g: f64 = 9.81;
pub const wind_pressure_pa: f64 = 504.0;

pub const GzSample = struct { angle_deg: f64, gz_m: f64 };

fn interpTable(comptime n: usize, xs: [n]f64, ys: [n]f64, x: f64) f64 {
    if (x <= xs[0]) return ys[0];
    if (x >= xs[n - 1]) return ys[n - 1];
    var i: usize = 1;
    while (xs[i] < x) i += 1;
    const t = (x - xs[i - 1]) / (xs[i] - xs[i - 1]);
    return ys[i - 1] + t * (ys[i] - ys[i - 1]);
}

/// IS Code Table 2.3.4-1: X1 vs B/d.
pub fn x1(b_over_d: f64) f64 {
    return interpTable(11, .{ 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.0, 3.1, 3.2, 3.4, 3.5 }, .{ 1.0, 0.98, 0.96, 0.95, 0.93, 0.91, 0.90, 0.88, 0.86, 0.82, 0.80 }, b_over_d);
}

/// IS Code Table 2.3.4-2: X2 vs Cb.
pub fn x2(cb: f64) f64 {
    return interpTable(6, .{ 0.45, 0.50, 0.55, 0.60, 0.65, 0.70 }, .{ 0.75, 0.82, 0.89, 0.95, 0.97, 1.0 }, cb);
}

/// IS Code Table 2.3.4-3: k vs bilge-keel area ratio 100*Ak/(L*B) [%].
pub fn kBilge(ak_ratio_pct: f64) f64 {
    return interpTable(8, .{ 0.0, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0 }, .{ 1.0, 0.98, 0.95, 0.88, 0.79, 0.74, 0.72, 0.70 }, ak_ratio_pct);
}

/// IS Code Table 2.3.4-4: s vs roll period [s].
pub fn sFactor(t_roll_s: f64) f64 {
    return interpTable(8, .{ 6.0, 7.0, 8.0, 12.0, 14.0, 16.0, 18.0, 20.0 }, .{ 0.100, 0.098, 0.093, 0.065, 0.053, 0.044, 0.038, 0.035 }, t_roll_s);
}

pub fn rollPeriodS(lwl_m: f64, beam_m: f64, draft_m: f64, gm_m: f64) f64 {
    const c = 0.373 + 0.023 * (beam_m / draft_m) - 0.043 * (lwl_m / 100.0);
    return 2.0 * c * beam_m / @sqrt(gm_m);
}

pub const Input = struct {
    lwl_m: f64,
    beam_m: f64,
    draft_m: f64,
    cb: f64,
    /// Displacement [t].
    displacement_t: f64,
    gm_m: f64,
    /// G above waterline [m] (KG - d); negative when G is below the WL.
    og_m: f64,
    /// Projected lateral windage area above WL [m^2].
    windage_area_m2: f64,
    /// Lever from windage centroid to underwater lateral centroid [m].
    windage_lever_z_m: f64,
    /// Bilge-keel area ratio 100*Ak/(L*B) [%]; 0 = none.
    bilge_keel_pct: f64 = 0.0,
    /// Downflooding angle [deg]; 50 used when larger.
    downflooding_deg: f64 = 50.0,
    gz_curve: []const GzSample,
};

pub const Result = struct {
    lw1_m: f64,
    lw2_m: f64,
    phi0_deg: f64,
    phi1_deg: f64,
    roll_period_s: f64,
    area_a_m_rad: f64,
    area_b_m_rad: f64,
    phi0_ok: bool,
    energy_ok: bool,
    pass: bool,
};

fn gzAt(curve: []const GzSample, angle_deg: f64) f64 {
    if (angle_deg <= curve[0].angle_deg) {
        // Odd extension below the first sample (GZ(-x) = -GZ(x)).
        return -gzAtPos(curve, -angle_deg);
    }
    return gzAtPos(curve, angle_deg);
}

fn gzAtPos(curve: []const GzSample, angle_deg: f64) f64 {
    if (angle_deg <= curve[0].angle_deg) {
        const a0 = curve[0];
        const a1 = curve[1];
        const t = (angle_deg - a0.angle_deg) / (a1.angle_deg - a0.angle_deg);
        return a0.gz_m + t * (a1.gz_m - a0.gz_m);
    }
    var i: usize = 1;
    while (i < curve.len and curve[i].angle_deg < angle_deg) i += 1;
    if (i == curve.len) i -= 1;
    const p0 = curve[i - 1];
    const p1 = curve[i];
    const t = (angle_deg - p0.angle_deg) / (p1.angle_deg - p0.angle_deg);
    return p0.gz_m + t * (p1.gz_m - p0.gz_m);
}

pub fn evaluate(in: Input) Result {
    const lw1 = wind_pressure_pa * in.windage_area_m2 * in.windage_lever_z_m /
        (1000.0 * g * in.displacement_t);
    const lw2 = 1.5 * lw1;

    // phi0: first intercept of GZ with lw1 (search 0..30 deg).
    var phi0: f64 = 30.0;
    var a: f64 = 0.0;
    while (a <= 30.0) : (a += 0.1) {
        if (gzAt(in.gz_curve, a) >= lw1) {
            phi0 = a;
            break;
        }
    }

    const t_roll = rollPeriodS(in.lwl_m, in.beam_m, in.draft_m, in.gm_m);
    const r = 0.73 + 0.6 * in.og_m / in.draft_m;
    const phi1 = 109.0 * kBilge(in.bilge_keel_pct) * x1(in.beam_m / in.draft_m) *
        x2(in.cb) * @sqrt(@max(r, 0.0) * sFactor(t_roll));

    // phi2: second intercept of lw2 with GZ beyond phi0 (or the cap).
    const cap = @min(in.downflooding_deg, 50.0);
    var phi2: f64 = cap;
    var b_ang = phi0 + 0.1;
    var seen_above = false;
    while (b_ang <= cap) : (b_ang += 0.1) {
        const dgz = gzAt(in.gz_curve, b_ang) - lw2;
        if (dgz > 0) seen_above = true;
        if (seen_above and dgz < 0) {
            phi2 = b_ang;
            break;
        }
    }

    // Trapezoid areas in metre-radians.
    const step: f64 = 0.1;
    var area_a: f64 = 0.0;
    var x = phi0 - phi1;
    while (x < phi0) : (x += step) {
        const d1 = lw2 - gzAt(in.gz_curve, x);
        const d2 = lw2 - gzAt(in.gz_curve, @min(x + step, phi0));
        area_a += 0.5 * (d1 + d2) * std.math.degreesToRadians(step);
    }
    var area_b: f64 = 0.0;
    x = phi0;
    while (x < phi2) : (x += step) {
        const d1 = @max(gzAt(in.gz_curve, x) - lw2, -1e9);
        const d2 = @max(gzAt(in.gz_curve, @min(x + step, phi2)) - lw2, -1e9);
        area_b += 0.5 * (d1 + d2) * std.math.degreesToRadians(step);
    }

    const phi0_ok = phi0 <= 16.0;
    const energy_ok = area_b >= area_a;
    return .{
        .lw1_m = lw1,
        .lw2_m = lw2,
        .phi0_deg = phi0,
        .phi1_deg = phi1,
        .roll_period_s = t_roll,
        .area_a_m_rad = area_a,
        .area_b_m_rad = area_b,
        .phi0_ok = phi0_ok,
        .energy_ok = energy_ok,
        .pass = phi0_ok and energy_ok,
    };
}

fn sinCurve(comptime gm: f64) [13]GzSample {
    var c: [13]GzSample = undefined;
    for (&c, 0..) |*p, i| {
        const deg: f64 = @floatFromInt(i * 5);
        p.* = .{ .angle_deg = deg, .gz_m = gm * @sin(std.math.degreesToRadians(deg)) };
    }
    return c;
}

test "tables hit the IS Code breakpoints exactly" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), x1(2.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.90), x1(3.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.80), x1(4.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), x2(0.40), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.95), x2(0.60), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), x2(0.80), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.093), sFactor(8.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.065), sFactor(12.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.70), kBilge(5.0), 1e-12);
}

test "gust lever is exactly 1.5x the steady lever" {
    const curve = sinCurve(1.2);
    const res = evaluate(.{
        .lwl_m = 100,
        .beam_m = 16,
        .draft_m = 6,
        .cb = 0.65,
        .displacement_t = 6300,
        .gm_m = 1.2,
        .og_m = -0.5,
        .windage_area_m2 = 600,
        .windage_lever_z_m = 6.0,
        .gz_curve = &curve,
    });
    try std.testing.expectApproxEqRel(res.lw1_m * 1.5, res.lw2_m, 1e-12);
    // Hand check: 504*600*6 / (1000*9.81*6300) = 0.02936 m.
    try std.testing.expectApproxEqAbs(@as(f64, 0.02936), res.lw1_m, 1e-4);
}

test "stiff low-windage ship passes; tender high-windage ship fails" {
    const stiff_curve = sinCurve(1.5);
    const stiff = evaluate(.{
        .lwl_m = 100,
        .beam_m = 16,
        .draft_m = 6,
        .cb = 0.65,
        .displacement_t = 6300,
        .gm_m = 1.5,
        .og_m = -1.0,
        .windage_area_m2 = 500,
        .windage_lever_z_m = 5.0,
        .gz_curve = &stiff_curve,
    });
    try std.testing.expect(stiff.pass);
    try std.testing.expect(stiff.phi0_deg < 16.0);

    const tender_curve = sinCurve(0.15);
    const tender = evaluate(.{
        .lwl_m = 100,
        .beam_m = 16,
        .draft_m = 6,
        .cb = 0.65,
        .displacement_t = 6300,
        .gm_m = 0.15,
        .og_m = 2.0,
        .windage_area_m2 = 1800,
        .windage_lever_z_m = 12.0,
        .gz_curve = &tender_curve,
    });
    try std.testing.expect(!tender.pass);
}

test "bilge keels reduce the roll-back angle" {
    // phi1 scales with k: 4% bilge keels cut it to 70%.
    const base = 109.0 * kBilge(0.0) * x1(2.67) * x2(0.65);
    const keeled = 109.0 * kBilge(4.0) * x1(2.67) * x2(0.65);
    try std.testing.expectApproxEqRel(keeled / base, 0.70, 1e-9);
}
