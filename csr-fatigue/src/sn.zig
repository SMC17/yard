const std = @import("std");

pub const Error = error{
    NonPositiveStress,
    NonPositiveThickness,
    UnknownClass,
};

/// DNV-RP-C203 detail classes for in-air environment.
/// Each class has two linear slopes in log-log space joined at the
/// knee at N_q = 1e7 cycles per Table 2-1 (2024 edition); reference
/// thickness `t_ref` and thickness exponent `k` per Table 2-2.
pub const DetailClass = enum {
    B1,
    B2,
    C,
    C1,
    C2,
    D,
    E,
    F,
    F1,
    F3,
    G,
    W1,
    W2,
    W3,

    pub fn params(self: DetailClass) Params {
        // Values from DNV-RP-C203 (2024) Table 2-1 (air).
        return switch (self) {
            .B1 => .{ .m1 = 4.0, .log_a1 = 15.117, .m2 = 5.0, .log_a2 = 17.146, .t_ref = 25.0, .k = 0.0 },
            .B2 => .{ .m1 = 4.0, .log_a1 = 14.885, .m2 = 5.0, .log_a2 = 16.856, .t_ref = 25.0, .k = 0.0 },
            .C => .{ .m1 = 3.0, .log_a1 = 12.592, .m2 = 5.0, .log_a2 = 16.320, .t_ref = 25.0, .k = 0.05 },
            .C1 => .{ .m1 = 3.0, .log_a1 = 12.449, .m2 = 5.0, .log_a2 = 16.081, .t_ref = 25.0, .k = 0.10 },
            .C2 => .{ .m1 = 3.0, .log_a1 = 12.301, .m2 = 5.0, .log_a2 = 15.835, .t_ref = 25.0, .k = 0.15 },
            .D => .{ .m1 = 3.0, .log_a1 = 12.164, .m2 = 5.0, .log_a2 = 15.606, .t_ref = 25.0, .k = 0.20 },
            .E => .{ .m1 = 3.0, .log_a1 = 12.010, .m2 = 5.0, .log_a2 = 15.350, .t_ref = 25.0, .k = 0.20 },
            .F => .{ .m1 = 3.0, .log_a1 = 11.855, .m2 = 5.0, .log_a2 = 15.091, .t_ref = 25.0, .k = 0.25 },
            .F1 => .{ .m1 = 3.0, .log_a1 = 11.699, .m2 = 5.0, .log_a2 = 14.832, .t_ref = 25.0, .k = 0.25 },
            .F3 => .{ .m1 = 3.0, .log_a1 = 11.546, .m2 = 5.0, .log_a2 = 14.576, .t_ref = 25.0, .k = 0.25 },
            .G => .{ .m1 = 3.0, .log_a1 = 11.398, .m2 = 5.0, .log_a2 = 14.330, .t_ref = 25.0, .k = 0.25 },
            .W1 => .{ .m1 = 3.0, .log_a1 = 11.261, .m2 = 5.0, .log_a2 = 14.101, .t_ref = 25.0, .k = 0.25 },
            .W2 => .{ .m1 = 3.0, .log_a1 = 11.107, .m2 = 5.0, .log_a2 = 13.845, .t_ref = 25.0, .k = 0.25 },
            .W3 => .{ .m1 = 3.0, .log_a1 = 10.970, .m2 = 5.0, .log_a2 = 13.617, .t_ref = 25.0, .k = 0.25 },
        };
    }
};

pub const Params = struct {
    m1: f64,
    log_a1: f64,
    m2: f64,
    log_a2: f64,
    /// Reference thickness [mm] for thickness reduction.
    t_ref: f64,
    /// Thickness exponent.
    k: f64,
};

/// Constant log_10 N at the knee per DNV-RP-C203 (air): N_q = 10^7.
pub const log_N_knee: f64 = 7.0;

/// Knee stress for an S-N curve. At log_10 N = 7, the slope changes
/// from m_1 to m_2; the corresponding stress is
/// delta_sigma_knee = 10^((log_a1 - log_N_knee) / m_1).
pub fn kneeStressMPa(p: Params) f64 {
    return std.math.pow(f64, 10.0, (p.log_a1 - log_N_knee) / p.m1);
}

/// Permissible cycles to failure N for a stress range delta_sigma [MPa]
/// and detail class, including thickness reduction for t > t_ref.
/// Returns +inf if delta_sigma_eff <= 0 (no damage accumulated).
pub fn cyclesToFailure(cls: DetailClass, delta_sigma_mpa: f64, thickness_mm: f64) Error!f64 {
    if (!(delta_sigma_mpa > 0)) return Error.NonPositiveStress;
    if (!(thickness_mm > 0)) return Error.NonPositiveThickness;
    const p = cls.params();
    var sigma_eff = delta_sigma_mpa;
    if (thickness_mm > p.t_ref) {
        const tf = std.math.pow(f64, thickness_mm / p.t_ref, p.k);
        sigma_eff *= tf;
    }
    const ds_knee = kneeStressMPa(p);
    const log_s = std.math.log10(sigma_eff);
    var log_N: f64 = undefined;
    if (sigma_eff >= ds_knee) {
        // High-stress branch: m_1, log_a1.
        log_N = p.log_a1 - p.m1 * log_s;
    } else {
        // Low-stress branch: m_2, log_a2.
        log_N = p.log_a2 - p.m2 * log_s;
    }
    return std.math.pow(f64, 10.0, log_N);
}

test "D class knee stress" {
    const p = DetailClass.D.params();
    const ds = kneeStressMPa(p);
    // delta_sigma_knee = 10^((12.164 - 7) / 3) = 10^(1.7213...) ~= 52.63 MPa.
    try std.testing.expectApproxEqAbs(@as(f64, 52.63), ds, 0.05);
}

test "D class at high stress uses m_1 slope" {
    // delta_sigma = 160 MPa (above knee). log N = 12.164 - 3 log(160).
    const N = try cyclesToFailure(.D, 160.0, 25.0);
    const log_N = 12.164 - 3.0 * std.math.log10(160.0);
    const expected = std.math.pow(f64, 10.0, log_N);
    try std.testing.expectApproxEqAbs(expected, N, 1.0);
    // Sanity: ~3.5e5 cycles for D at 160 MPa.
    try std.testing.expect(N > 3e5 and N < 4e5);
}

test "D class at low stress uses m_2 slope" {
    // delta_sigma = 30 MPa (well below knee ~ 52.6 MPa).
    const N = try cyclesToFailure(.D, 30.0, 25.0);
    const log_N = 15.606 - 5.0 * std.math.log10(30.0);
    const expected = std.math.pow(f64, 10.0, log_N);
    try std.testing.expectApproxEqAbs(expected, N, 1.0);
}

test "D class at knee yields N = 1e7" {
    const ds_knee = kneeStressMPa(DetailClass.D.params());
    const N = try cyclesToFailure(.D, ds_knee, 25.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1e7), N, 1e3);
}

test "thickness reduction increases damage for thick plates" {
    // D class, t = 50 mm > t_ref = 25 mm, k = 0.2.
    // Thickness factor = (50/25)^0.2 = 2^0.2 ~= 1.149.
    // sigma_eff = 1.149 * 160 = 183.8 MPa.
    const N_thick = try cyclesToFailure(.D, 160.0, 50.0);
    const N_ref = try cyclesToFailure(.D, 160.0, 25.0);
    try std.testing.expect(N_thick < N_ref);
    const ratio_expected = std.math.pow(f64, 1.149, 3.0); // m_1 = 3
    const ratio_got = N_ref / N_thick;
    try std.testing.expectApproxEqAbs(ratio_expected, ratio_got, 0.05);
}

test "C class is more durable than D at same stress" {
    const N_c = try cyclesToFailure(.C, 160.0, 25.0);
    const N_d = try cyclesToFailure(.D, 160.0, 25.0);
    try std.testing.expect(N_c > N_d);
}

test "W3 class is least durable at same stress" {
    const N_d = try cyclesToFailure(.D, 100.0, 25.0);
    const N_w3 = try cyclesToFailure(.W3, 100.0, 25.0);
    try std.testing.expect(N_w3 < N_d);
}

test "non-positive stress rejected" {
    try std.testing.expectError(Error.NonPositiveStress, cyclesToFailure(.D, 0.0, 25.0));
    try std.testing.expectError(Error.NonPositiveStress, cyclesToFailure(.D, -5.0, 25.0));
}

test "non-positive thickness rejected" {
    try std.testing.expectError(Error.NonPositiveThickness, cyclesToFailure(.D, 100.0, 0.0));
}
