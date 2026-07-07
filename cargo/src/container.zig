const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveTiers,
    InvalidContainer,
    NonPositiveLength,
};

/// ISO 668 container length classification.
pub const ContainerSize = enum {
    /// 20-ft = 1 TEU.
    TEU_20ft,
    /// 40-ft = 2 TEU = 1 FEU.
    FEU_40ft,
    /// 45-ft = 2 TEU (carried at 2 TEU stack count).
    HC_45ft,

    /// External length [m] per ISO 668.
    pub fn lengthM(self: ContainerSize) f64 {
        return switch (self) {
            .TEU_20ft => 6.058,
            .FEU_40ft => 12.192,
            .HC_45ft => 13.716,
        };
    }

    /// Equivalent TEU count.
    pub fn teu(self: ContainerSize) f64 {
        return switch (self) {
            .TEU_20ft => 1.0,
            .FEU_40ft => 2.0,
            .HC_45ft => 2.0,
        };
    }

    /// Maximum gross mass [kg] per CSC plate for steel dry van.
    pub fn maxGrossMassKg(self: ContainerSize) f64 {
        return switch (self) {
            .TEU_20ft => 30_480.0,
            .FEU_40ft => 32_500.0,
            .HC_45ft => 32_500.0,
        };
    }

    /// Tare mass [kg] for a representative steel dry-van container.
    pub fn typicalTareKg(self: ContainerSize) f64 {
        return switch (self) {
            .TEU_20ft => 2_330.0,
            .FEU_40ft => 3_750.0,
            .HC_45ft => 4_200.0,
        };
    }

    /// Maximum payload [kg] = max gross - tare.
    pub fn maxPayloadKg(self: ContainerSize) f64 {
        return self.maxGrossMassKg() - self.typicalTareKg();
    }
};

/// Stacking weight on the bottom container in a stack of `tiers`
/// containers each at gross mass `m_gross`. The bottom corner posts
/// must support the (tiers - 1) containers above it:
///   W_stack = (tiers - 1) * m_gross * g.
pub fn stackingWeightN(
    tiers: u32,
    m_gross_kg: f64,
    g_mps2: f64,
) Error!f64 {
    if (tiers == 0) return Error.NonPositiveTiers;
    if (!(m_gross_kg > 0)) return Error.NonPositiveMass;
    const t_f: f64 = @floatFromInt(tiers - 1);
    return t_f * m_gross_kg * g_mps2;
}

/// CSC plate stacking load: each corner post must carry the
/// per-post share:
///   F_post = W_stack / 4.
pub fn perCornerPostLoadN(W_stack_n: f64) f64 {
    return W_stack_n / 4.0;
}

/// CSC standard stacking-test rating: 192 000 kg per pair of corner
/// fittings per ISO 1496-1. Per-post that is 96 000 kg * g.
pub const csc_stacking_rating_per_post_n: f64 = 96_000.0 * 9.80665;

pub const Verdict = enum { pass, fail };

/// Stacking verdict against the CSC rating.
pub fn stackingVerdict(F_post_n: f64) Verdict {
    if (F_post_n <= csc_stacking_rating_per_post_n) return .pass;
    return .fail;
}

/// Total TEU on a single bay of `rows` rows and `tiers` tiers, all
/// 20-ft containers:
///   TEU = rows * tiers.
pub fn bayTeuCount(rows: u32, tiers: u32) Error!u32 {
    if (rows == 0 or tiers == 0) return Error.NonPositiveTiers;
    return rows * tiers;
}

test "TEU length 6.058 m" {
    try std.testing.expectApproxEqAbs(@as(f64, 6.058), ContainerSize.TEU_20ft.lengthM(), 1e-12);
}

test "FEU length 12.192 m" {
    try std.testing.expectApproxEqAbs(@as(f64, 12.192), ContainerSize.FEU_40ft.lengthM(), 1e-12);
}

test "TEU count for FEU is 2" {
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), ContainerSize.FEU_40ft.teu(), 1e-12);
}

test "TEU max gross 30480 kg" {
    try std.testing.expectApproxEqAbs(@as(f64, 30_480.0), ContainerSize.TEU_20ft.maxGrossMassKg(), 1e-12);
}

test "FEU max gross 32500 kg" {
    try std.testing.expectApproxEqAbs(@as(f64, 32_500.0), ContainerSize.FEU_40ft.maxGrossMassKg(), 1e-12);
}

test "TEU payload = gross - tare" {
    try std.testing.expectApproxEqAbs(@as(f64, 28_150.0), ContainerSize.TEU_20ft.maxPayloadKg(), 1e-12);
}

test "stacking weight: 6 tiers of 20 t" {
    const W = try stackingWeightN(6, 20_000.0, 9.80665);
    // 5 * 20000 * 9.80665 = 980 665 N.
    try std.testing.expectApproxEqAbs(@as(f64, 980_665.0), W, 1e-3);
}

test "stacking weight: single tier is zero" {
    const W = try stackingWeightN(1, 20_000.0, 9.80665);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), W, 1e-12);
}

test "stacking weight scales linearly with mass" {
    const W1 = try stackingWeightN(6, 10_000.0, 9.80665);
    const W2 = try stackingWeightN(6, 20_000.0, 9.80665);
    try std.testing.expectApproxEqAbs(2.0 * W1, W2, 1e-3);
}

test "per-corner-post is W_stack / 4" {
    const F = perCornerPostLoadN(400_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 100_000.0), F, 1e-12);
}

test "stacking verdict pass at typical 6-tier stack" {
    const W = try stackingWeightN(6, 20_000.0, 9.80665);
    const F = perCornerPostLoadN(W);
    try std.testing.expectEqual(Verdict.pass, stackingVerdict(F));
}

test "stacking verdict fail at extreme overload" {
    try std.testing.expectEqual(Verdict.fail, stackingVerdict(2.0e6));
}

test "bay TEU count: 12 rows x 8 tiers = 96" {
    const n = try bayTeuCount(12, 8);
    try std.testing.expectEqual(@as(u32, 96), n);
}

test "input rejection: zero tiers" {
    try std.testing.expectError(Error.NonPositiveTiers, stackingWeightN(0, 10_000.0, 9.80665));
}

test "input rejection: zero mass" {
    try std.testing.expectError(Error.NonPositiveMass, stackingWeightN(6, 0.0, 9.80665));
}
