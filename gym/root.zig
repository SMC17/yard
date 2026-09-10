//! L0/L1 mirror for Yard-Sea-v0 (box-like particulars).
//! Parity target: yard_sea_v0.hull + yard_sea_v0.resistance_l1 (Python).
const std = @import("std");
const math = std.math;

pub const RHO_SW: f64 = 1025.0;
pub const G: f64 = 9.80665;
pub const NU: f64 = 1.19e-6;

pub const CB_MIN: f64 = 0.45;
pub const CB_MAX: f64 = 0.95;
pub const TB_MIN: f64 = 0.15;
pub const TB_MAX: f64 = 0.55;
pub const LB_MIN: f64 = 3.0;
pub const LB_MAX: f64 = 12.0;
pub const GM_MIN: f64 = 0.15;
pub const LCB_FRAC_MIN: f64 = -0.05;
pub const LCB_FRAC_MAX: f64 = 0.05;

pub const Hull = struct {
    L: f64 = 120,
    B: f64 = 20,
    T: f64 = 8,
    Cb: f64 = 0.75,
    lcb_frac: f64 = 0,
    kg_frac: f64 = 0.55,
    Fn: f64 = 0.20,
};

pub fn volume(h: Hull) f64 {
    return h.L * h.B * h.T * h.Cb;
}

pub fn displacement_t(h: Hull) f64 {
    return volume(h) * RHO_SW / 1000.0;
}

pub fn kb(h: Hull) f64 {
    return 0.5 * h.T;
}

pub fn bm_t(h: Hull) f64 {
    const v = volume(h);
    if (v <= 0) return 0.0;
    const i_t = h.L * h.B * h.B * h.B / 12.0;
    return i_t / v;
}

pub fn depth_approx(h: Hull) f64 {
    return @max(h.T * 1.25, h.T + 0.5);
}

pub fn kg(h: Hull) f64 {
    return h.kg_frac * depth_approx(h);
}

pub fn gm0(h: Hull) f64 {
    return kb(h) + bm_t(h) - kg(h);
}

pub fn wetted_approx(h: Hull) f64 {
    return h.L * (2.0 * h.T + h.B) * (0.9 + 0.1 * h.Cb);
}

pub fn l0_feasible(h: Hull) bool {
    return evaluate_l0(h).feasible;
}

pub const L0Report = struct {
    feasible: bool,
    n_violations: usize,
    // fixed buffer of violation tags (truncated)
    violations: [8][]const u8,
    L_B: f64,
    T_B: f64,
    Cb: f64,
    gm0_m: f64,
    volume_m3: f64,
    displacement_t: f64,
};

pub fn evaluate_l0(h: Hull) L0Report {
    var vios: [8][]const u8 = undefined;
    var n: usize = 0;
    const push = struct {
        fn f(buf: *[8][]const u8, count: *usize, s: []const u8) void {
            if (count.* < buf.len) {
                buf[count.*] = s;
                count.* += 1;
            }
        }
    }.f;

    if (h.L <= 0 or h.B <= 0 or h.T <= 0) push(&vios, &n, "non_positive_particulars");
    if (volume(h) <= 0) push(&vios, &n, "non_positive_volume");

    const lb = if (h.B != 0) h.L / h.B else math.inf(f64);
    const tb = if (h.B != 0) h.T / h.B else math.inf(f64);
    if (!(LB_MIN <= lb and lb <= LB_MAX)) push(&vios, &n, "L_B_out_of_band");
    if (!(TB_MIN <= tb and tb <= TB_MAX)) push(&vios, &n, "T_B_out_of_band");
    if (!(CB_MIN <= h.Cb and h.Cb <= CB_MAX)) push(&vios, &n, "Cb_out_of_band");
    if (!(LCB_FRAC_MIN <= h.lcb_frac and h.lcb_frac <= LCB_FRAC_MAX)) push(&vios, &n, "lcb_frac_out_of_band");
    const gm = gm0(h);
    if (gm < GM_MIN) push(&vios, &n, "gm0_below_floor");
    if (h.B / (2.0 * h.T) <= 0.8) push(&vios, &n, "hydrostatic_model_outside_envelope");

    return .{
        .feasible = n == 0,
        .n_violations = n,
        .violations = vios,
        .L_B = lb,
        .T_B = tb,
        .Cb = h.Cb,
        .gm0_m = gm,
        .volume_m3 = volume(h),
        .displacement_t = displacement_t(h),
    };
}

pub fn ittc57_cf(rn_in: f64) f64 {
    var rn = rn_in;
    if (rn <= 1e5) rn = 1e5;
    const den = math.log10(rn) - 2.0;
    return 0.075 / (den * den);
}

pub const ResistanceResult = struct {
    Fn: f64,
    Rn: f64,
    Cf: f64,
    k1: f64,
    Cw: f64,
    Rt_N: f64,
    Ct: f64,
};

/// Holtrop-simplified L1 matching Python yard_sea_v0.resistance_l1.estimate_resistance.
pub fn estimate_resistance(h: Hull) ResistanceResult {
    const L = h.L;
    const B = h.B;
    const T = h.T;
    const Cb = h.Cb;
    const Fn = h.Fn;
    const U = Fn * @sqrt(G * L);
    const S = wetted_approx(h);
    const Rn = U * L / NU;
    const Cf = ittc57_cf(Rn);

    var lr = L * (1.0 - Cb + 0.06 * Cb * (h.lcb_frac * 4.0 + 1.0) / (4.0 * Cb - 1.0 + 1e-6));
    lr = @max(0.6 * L, @min(L, lr));
    const c14 = 1.0 + 0.011 * 10.0;
    var k1 = 0.93 + 0.487118 * c14 * math.pow(f64, B / L, 1.06806) * math.pow(f64, T / L, 0.46106) *
        math.pow(f64, L / lr, 0.121563) * math.pow(f64, (L * L * L) / @max(volume(h), 1.0), 0.364569) *
        math.pow(f64, 1.0 - Cb, -0.604247);
    k1 = @max(0.1, @min(0.8, k1 - 1.0));

    const c7 = B / L;
    var c1: f64 = undefined;
    if (c7 < 0.11) {
        c1 = 0.229577 * math.pow(f64, c7, 0.33333);
    } else if (c7 > 0.25) {
        c1 = 0.5 - 0.0625 / c7;
    } else {
        c1 = 2223105.0 * math.pow(f64, c7, 3.78613) * math.pow(f64, T / B, 1.07961) *
            math.pow(f64, 90.0 - 70.0 * Cb, -1.37565);
        c1 = @max(0.5, @min(50.0, c1 / 1e4));
    }

    const d: f64 = -0.9;
    const m1 = 0.0140407 * (L / T) - 1.75254 * math.pow(f64, volume(h), 1.0 / 3.0) / L - 4.79323 * B / L - c1;
    var Cw = c1 * 0.02 * @exp(m1 * math.pow(f64, Fn, d) + 0.0 * @cos(h.lcb_frac * math.pi));
    Cw = @max(0.0, @min(0.05, Cw * (1.0 + 2.0 * (Fn - 0.15) * (Fn - 0.15))));

    var Ca = 0.006 * math.pow(f64, L + 100.0, -0.16) - 0.00205;
    Ca = @max(0.0, Ca);

    const Ct = Cf * (1.0 + k1) + Cw + Ca;
    const Rt = 0.5 * RHO_SW * U * U * S * Ct;
    return .{
        .Fn = Fn,
        .Rn = Rn,
        .Cf = Cf,
        .k1 = k1,
        .Cw = Cw,
        .Rt_N = Rt,
        .Ct = Ct,
    };
}

test "default hull feasible" {
    try std.testing.expect(l0_feasible(.{}));
}

test "bad cb rejected" {
    try std.testing.expect(!l0_feasible(.{ .Cb = 0.2 }));
}

test "default gm0 matches python scale" {
    const g = gm0(.{});
    // Python default: kb=4, bm=L*B^3/12/V = 120*8000/12/14400 = 5.555..., kg=0.55*10=5.5 → gm≈4.055
    try std.testing.expect(@abs(g - 4.055555555555555) < 1e-9);
}

test "default Ct finite positive" {
    const r = estimate_resistance(.{});
    try std.testing.expect(r.Ct > 0 and r.Ct < 0.1);
    try std.testing.expect(r.Rt_N > 0);
}
