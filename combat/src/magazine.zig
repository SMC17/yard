const std = @import("std");

pub const Error = error{
    NonPositiveExplosive,
    InvalidCategory,
    NonPositiveDistance,
};

/// STANAG 4439 / DoD 6055.09-M quantity-distance category.
pub const QDCategory = enum {
    /// IBD (Inhabited Building Distance).
    IBD,
    /// PTRD (Public Traffic Route Distance).
    PTRD,
    /// IMD (Intermagazine Distance) between PES (Potential
    /// Explosion Site) and exposed magazine.
    IMD,
    /// IMD with shielded buildings.
    IMD_shielded,

    /// K-factor [m / kg^(1/3)] per AASTP-1.
    pub fn kFactor(self: QDCategory) f64 {
        return switch (self) {
            .IBD => 22.2,
            .PTRD => 14.8,
            .IMD => 8.0,
            .IMD_shielded => 4.0,
        };
    }
};

/// Quantity-distance separation:
///   D_min = K_factor * NEW^(1/3)
/// where NEW is the net explosive weight (TNT equivalent) in kg
/// and K_factor is the AASTP-1 / STANAG 4439 coefficient.
pub fn quantityDistanceM(
    NEW_kg: f64,
    category: QDCategory,
) Error!f64 {
    if (!(NEW_kg > 0)) return Error.NonPositiveExplosive;
    return category.kFactor() * std.math.cbrt(NEW_kg);
}

/// Maximum credible event (MCE) [kg TNT eq] from a single magazine
/// with N munitions each carrying NEW_each:
///   MCE = N * NEW_each.
pub fn maximumCredibleEventKg(N: u32, NEW_each_kg: f64) Error!f64 {
    if (N == 0) return Error.InvalidCategory;
    if (!(NEW_each_kg > 0)) return Error.NonPositiveExplosive;
    const n_f: f64 = @floatFromInt(N);
    return n_f * NEW_each_kg;
}

pub const Verdict = enum { pass, fail };

/// Verdict: actual distance vs required QD.
pub fn separationVerdict(
    actual_m: f64,
    NEW_kg: f64,
    category: QDCategory,
) Error!Verdict {
    if (!(actual_m >= 0)) return Error.NonPositiveDistance;
    const D_req = try quantityDistanceM(NEW_kg, category);
    if (actual_m >= D_req) return .pass;
    return .fail;
}

test "IBD K factor 22.2 m/kg^(1/3)" {
    try std.testing.expectApproxEqAbs(@as(f64, 22.2), QDCategory.IBD.kFactor(), 1e-12);
}

test "PTRD K factor 14.8 m/kg^(1/3)" {
    try std.testing.expectApproxEqAbs(@as(f64, 14.8), QDCategory.PTRD.kFactor(), 1e-12);
}

test "IBD > PTRD > IMD > IMD_shielded" {
    try std.testing.expect(QDCategory.IBD.kFactor() > QDCategory.PTRD.kFactor());
    try std.testing.expect(QDCategory.PTRD.kFactor() > QDCategory.IMD.kFactor());
    try std.testing.expect(QDCategory.IMD.kFactor() > QDCategory.IMD_shielded.kFactor());
}

test "QD at 1000 kg NEW IBD: 22.2 * 10 = 222 m" {
    const D = try quantityDistanceM(1000.0, .IBD);
    try std.testing.expectApproxEqAbs(@as(f64, 222.0), D, 1e-9);
}

test "QD scales with NEW^(1/3)" {
    const D1 = try quantityDistanceM(1000.0, .IBD);
    const D2 = try quantityDistanceM(8000.0, .IBD);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), D2 / D1, 1e-9);
}

test "MCE: 100 munitions x 10 kg each = 1000 kg" {
    const MCE = try maximumCredibleEventKg(100, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), MCE, 1e-12);
}

test "MCE scales linearly with N" {
    const M1 = try maximumCredibleEventKg(100, 10.0);
    const M2 = try maximumCredibleEventKg(200, 10.0);
    try std.testing.expectApproxEqAbs(2.0 * M1, M2, 1e-12);
}

test "verdict pass when actual >= required" {
    try std.testing.expectEqual(Verdict.pass, try separationVerdict(250.0, 1000.0, .IBD));
}

test "verdict pass at exactly required" {
    try std.testing.expectEqual(Verdict.pass, try separationVerdict(222.0, 1000.0, .IBD));
}

test "verdict fail when actual below required" {
    try std.testing.expectEqual(Verdict.fail, try separationVerdict(200.0, 1000.0, .IBD));
}

test "QD ordering: IBD > IMD at same NEW" {
    const D_IBD = try quantityDistanceM(1000.0, .IBD);
    const D_IMD = try quantityDistanceM(1000.0, .IMD);
    try std.testing.expect(D_IBD > D_IMD);
}

test "input rejection: zero NEW" {
    try std.testing.expectError(
        Error.NonPositiveExplosive,
        quantityDistanceM(0.0, .IBD),
    );
}

test "input rejection: zero munition count" {
    try std.testing.expectError(
        Error.InvalidCategory,
        maximumCredibleEventKg(0, 10.0),
    );
}

test "input rejection: negative actual distance" {
    try std.testing.expectError(
        Error.NonPositiveDistance,
        separationVerdict(-1.0, 1000.0, .IBD),
    );
}
