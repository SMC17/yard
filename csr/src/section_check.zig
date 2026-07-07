// IACS Common Structural Rules section-modulus check across multiple
// loading conditions.
//
// For each loading condition the bending-stress check is
//
//   sigma = |M_sw + M_wv| / Z_net <= sigma_perm
//
// where
//   M_sw       still-water bending moment (kN*m, positive hogging)
//   M_wv       wave-induced bending moment (kN*m, sign by mode)
//   Z_net      net section modulus after corrosion deduction (m^3)
//   sigma_perm = 175 / k          (N/mm^2; UR S4 material factor k)
//
// Net section modulus is the as-built section modulus minus the
// corrosion-deduction reduction:
//
//   Z_net = Z_gross - delta_Z_corrosion
//
// The caller provides the as-built Z and the per-condition corrosion
// deduction (mm of plate wastage applied to the hull-girder geometry,
// scaled to delta_Z).

const std = @import("std");

pub const Error = error{
    NonPositiveSectionModulus,
    NegativeDeduction,
    InvalidMaterialFactor,
};

pub const SteelGrade = enum {
    mild,
    ht32,
    ht36,
    ht40,

    pub fn k(self: SteelGrade) f64 {
        return switch (self) {
            .mild => 1.00,
            .ht32 => 0.78,
            .ht36 => 0.72,
            .ht40 => 0.66,
        };
    }
};

pub const Verdict = enum { pass, fail };

pub const LoadingCondition = struct {
    name: []const u8,
    M_sw_hog_kNm: f64,
    M_sw_sag_kNm: f64,
    M_wv_hog_kNm: f64,
    M_wv_sag_kNm: f64,
    delta_Z_corrosion_m3: f64,
};

pub const Section = struct {
    Z_gross_m3: f64,
    grade: SteelGrade,
};

pub const Result = struct {
    name: []const u8,
    hog_stress_MPa: f64,
    sag_stress_MPa: f64,
    sigma_perm_MPa: f64,
    Z_net_m3: f64,
    verdict_hog: Verdict,
    verdict_sag: Verdict,
    overall: Verdict,
    margin_hog: f64,
    margin_sag: f64,
};

/// Permissible normal stress per UR S4 material factor.
pub fn permissibleStressMpa(grade: SteelGrade) Error!f64 {
    const kv = grade.k();
    if (kv <= 0.0) return Error.InvalidMaterialFactor;
    return 175.0 / kv;
}

/// Evaluate one loading condition.
pub fn evaluate(condition: LoadingCondition, section: Section) Error!Result {
    if (section.Z_gross_m3 <= 0.0) return Error.NonPositiveSectionModulus;
    if (condition.delta_Z_corrosion_m3 < 0.0) return Error.NegativeDeduction;
    if (condition.delta_Z_corrosion_m3 >= section.Z_gross_m3) return Error.NonPositiveSectionModulus;

    const Z_net = section.Z_gross_m3 - condition.delta_Z_corrosion_m3;
    const sigma_perm = try permissibleStressMpa(section.grade);

    // Stress in MPa from moment in kN*m and Z in m^3:
    // sigma [N/mm^2] = M [kN*m] / Z [m^3] / 1000.
    const M_hog = @abs(condition.M_sw_hog_kNm + condition.M_wv_hog_kNm);
    const M_sag = @abs(condition.M_sw_sag_kNm + condition.M_wv_sag_kNm);
    const sigma_hog = M_hog / (Z_net * 1.0e3);
    const sigma_sag = M_sag / (Z_net * 1.0e3);

    const v_hog: Verdict = if (sigma_hog <= sigma_perm) .pass else .fail;
    const v_sag: Verdict = if (sigma_sag <= sigma_perm) .pass else .fail;
    const overall: Verdict = if (v_hog == .pass and v_sag == .pass) .pass else .fail;

    return .{
        .name = condition.name,
        .hog_stress_MPa = sigma_hog,
        .sag_stress_MPa = sigma_sag,
        .sigma_perm_MPa = sigma_perm,
        .Z_net_m3 = Z_net,
        .verdict_hog = v_hog,
        .verdict_sag = v_sag,
        .overall = overall,
        .margin_hog = sigma_perm - sigma_hog,
        .margin_sag = sigma_perm - sigma_sag,
    };
}

/// Aggregate verdict across a list of loading conditions: pass iff every
/// condition individually passes.
pub fn aggregateVerdict(results: []const Result) Verdict {
    for (results) |r| {
        if (r.overall == .fail) return .fail;
    }
    return .pass;
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "permissibleStressMpa matches UR S4 values" {
    try expectApproxEqAbs(@as(f64, 175.0), try permissibleStressMpa(.mild), 1e-12);
    try expectApproxEqRel(@as(f64, 175.0 / 0.78), try permissibleStressMpa(.ht32), 1e-12);
    try expectApproxEqRel(@as(f64, 175.0 / 0.72), try permissibleStressMpa(.ht36), 1e-12);
    try expectApproxEqRel(@as(f64, 175.0 / 0.66), try permissibleStressMpa(.ht40), 1e-12);
}

test "evaluate passes a well-designed bulker condition" {
    // Hughes/Paik bulker-style example: L=200, B=32, C_B=0.85, M_wv_hog ~ 2.016e6 kN*m.
    // Take Z = 12 m^3 (slightly above the UR S11 minimum).
    const c: LoadingCondition = .{
        .name = "Full load departure",
        .M_sw_hog_kNm = 1.0e6,
        .M_sw_sag_kNm = -5.0e5,
        .M_wv_hog_kNm = 2.0e6,
        .M_wv_sag_kNm = -2.1e6,
        .delta_Z_corrosion_m3 = 0.5,
    };
    const s: Section = .{ .Z_gross_m3 = 20.0, .grade = .mild };
    const r = try evaluate(c, s);
    // sigma_hog = 3.0e6 / (19.5 * 1e3) = 153.8 MPa < 175.
    try std.testing.expect(r.verdict_hog == .pass);
    try std.testing.expect(r.verdict_sag == .pass);
    try std.testing.expect(r.overall == .pass);
    try expectApproxEqAbs(@as(f64, 153.846), r.hog_stress_MPa, 1e-2);
}

test "evaluate fails when combined moment exceeds permissible" {
    const c: LoadingCondition = .{
        .name = "Overloaded",
        .M_sw_hog_kNm = 2.0e6,
        .M_sw_sag_kNm = -2.0e6,
        .M_wv_hog_kNm = 2.0e6,
        .M_wv_sag_kNm = -2.0e6,
        .delta_Z_corrosion_m3 = 0.0,
    };
    const s: Section = .{ .Z_gross_m3 = 15.0, .grade = .mild };
    const r = try evaluate(c, s);
    // sigma_hog = 4.0e6 / (15 * 1e3) = 266.7 MPa > 175.
    try std.testing.expect(r.verdict_hog == .fail);
    try std.testing.expect(r.overall == .fail);
}

test "evaluate rejects non-positive Z" {
    const c: LoadingCondition = .{
        .name = "x",
        .M_sw_hog_kNm = 1.0,
        .M_sw_sag_kNm = -1.0,
        .M_wv_hog_kNm = 1.0,
        .M_wv_sag_kNm = -1.0,
        .delta_Z_corrosion_m3 = 0.0,
    };
    var s: Section = .{ .Z_gross_m3 = 0.0, .grade = .mild };
    try std.testing.expectError(Error.NonPositiveSectionModulus, evaluate(c, s));
    s.Z_gross_m3 = -1.0;
    try std.testing.expectError(Error.NonPositiveSectionModulus, evaluate(c, s));
}

test "evaluate rejects negative corrosion deduction" {
    const c: LoadingCondition = .{
        .name = "x",
        .M_sw_hog_kNm = 1.0,
        .M_sw_sag_kNm = -1.0,
        .M_wv_hog_kNm = 1.0,
        .M_wv_sag_kNm = -1.0,
        .delta_Z_corrosion_m3 = -0.1,
    };
    const s: Section = .{ .Z_gross_m3 = 1.0, .grade = .mild };
    try std.testing.expectError(Error.NegativeDeduction, evaluate(c, s));
}

test "evaluate rejects corrosion deduction larger than Z" {
    const c: LoadingCondition = .{
        .name = "x",
        .M_sw_hog_kNm = 1.0,
        .M_sw_sag_kNm = -1.0,
        .M_wv_hog_kNm = 1.0,
        .M_wv_sag_kNm = -1.0,
        .delta_Z_corrosion_m3 = 10.0,
    };
    const s: Section = .{ .Z_gross_m3 = 1.0, .grade = .mild };
    try std.testing.expectError(Error.NonPositiveSectionModulus, evaluate(c, s));
}

test "Higher-strength steel allows higher stress" {
    const c: LoadingCondition = .{
        .name = "x",
        .M_sw_hog_kNm = 1.0e6,
        .M_sw_sag_kNm = -1.0e6,
        .M_wv_hog_kNm = 2.0e6,
        .M_wv_sag_kNm = -2.0e6,
        .delta_Z_corrosion_m3 = 0.0,
    };
    const s_mild: Section = .{ .Z_gross_m3 = 15.0, .grade = .mild };
    const s_ht40: Section = .{ .Z_gross_m3 = 15.0, .grade = .ht40 };
    const r_mild = try evaluate(c, s_mild);
    const r_ht40 = try evaluate(c, s_ht40);
    // Same physical stress; different permissible.
    try expectApproxEqRel(r_mild.hog_stress_MPa, r_ht40.hog_stress_MPa, 1e-12);
    try std.testing.expect(r_ht40.sigma_perm_MPa > r_mild.sigma_perm_MPa);
}

test "aggregateVerdict returns fail if any condition fails" {
    const results = [_]Result{
        .{ .name = "a", .hog_stress_MPa = 100, .sag_stress_MPa = 100, .sigma_perm_MPa = 175, .Z_net_m3 = 1, .verdict_hog = .pass, .verdict_sag = .pass, .overall = .pass, .margin_hog = 75, .margin_sag = 75 },
        .{ .name = "b", .hog_stress_MPa = 200, .sag_stress_MPa = 100, .sigma_perm_MPa = 175, .Z_net_m3 = 1, .verdict_hog = .fail, .verdict_sag = .pass, .overall = .fail, .margin_hog = -25, .margin_sag = 75 },
    };
    try std.testing.expectEqual(Verdict.fail, aggregateVerdict(&results));
}

test "aggregateVerdict returns pass if all conditions pass" {
    const results = [_]Result{
        .{ .name = "a", .hog_stress_MPa = 100, .sag_stress_MPa = 100, .sigma_perm_MPa = 175, .Z_net_m3 = 1, .verdict_hog = .pass, .verdict_sag = .pass, .overall = .pass, .margin_hog = 75, .margin_sag = 75 },
        .{ .name = "b", .hog_stress_MPa = 120, .sag_stress_MPa = 130, .sigma_perm_MPa = 175, .Z_net_m3 = 1, .verdict_hog = .pass, .verdict_sag = .pass, .overall = .pass, .margin_hog = 55, .margin_sag = 45 },
    };
    try std.testing.expectEqual(Verdict.pass, aggregateVerdict(&results));
}

test "margin_hog and margin_sag are sigma_perm minus stress" {
    const c: LoadingCondition = .{
        .name = "x",
        .M_sw_hog_kNm = 1.0e6,
        .M_sw_sag_kNm = -1.0e6,
        .M_wv_hog_kNm = 1.0e6,
        .M_wv_sag_kNm = -1.0e6,
        .delta_Z_corrosion_m3 = 0.0,
    };
    const s: Section = .{ .Z_gross_m3 = 20.0, .grade = .mild };
    const r = try evaluate(c, s);
    try expectApproxEqAbs(r.sigma_perm_MPa - r.hog_stress_MPa, r.margin_hog, 1e-12);
    try expectApproxEqAbs(r.sigma_perm_MPa - r.sag_stress_MPa, r.margin_sag, 1e-12);
}
