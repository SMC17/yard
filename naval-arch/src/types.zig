//! Shared domain types for yard composition workflows.
//! Primitive modules remain independent; compose/ and examples/ use these
//! as the interchange contract.

const std = @import("std");

/// Seawater defaults per validation_fixtures.md conventions.
pub const PhysicalConstants = struct {
    rho_seawater: f64 = 1025.0,
    rho_freshwater: f64 = 1000.0,
    g: f64 = 9.80665,
    nu: f64 = 1.18831e-6,

    pub const default: PhysicalConstants = .{};
};

/// Length between perpendiculars, beam, draft [m].
pub const PrincipalParticulars = struct {
    L: f64,
    B: f64,
    T: f64,

    pub fn lOverB(self: PrincipalParticulars) f64 {
        return self.L / self.B;
    }

    pub fn bOverT(self: PrincipalParticulars) f64 {
        return self.B / self.T;
    }
};

/// Rectangular tank for free-surface correction.
pub const TankSpec = struct {
    l_m: f64,
    b_m: f64,
    rho_fluid: f64,
};

/// Loading condition: vertical center of gravity and tank list.
pub const LoadingCondition = struct {
    kg_m: f64,
    tanks: []const TankSpec,
};

/// Hydrostatic summary from any hull primitive.
pub const Hydrostatics = struct {
    volume_m3: f64,
    displacement_kg: f64,
    kb_m: f64,
    bm_t_m: f64,
    km_t_m: f64,
    lcb_m: f64,
    c_b: f64,
};

/// Stability summary after free-surface correction.
pub const StabilitySummary = struct {
    gm0_m: f64,
    gm_corrected_m: f64,
    gg_prime_m: f64,
    wall_sided_valid: bool,
};

/// Single GZ sample point.
pub const GzSample = struct {
    angle_deg: f64,
    angle_rad: f64,
    gz_m: f64,
};

/// IMO IS Code 2008 Part A 2.2 criterion verdict.
pub const CriterionVerdict = enum { pass, fail };

/// Full regulatory evaluation result.
pub const IsCodeResult = struct {
    area_0_30: CriterionVerdict,
    area_0_40: CriterionVerdict,
    area_30_40: CriterionVerdict,
    gz_at_30: CriterionVerdict,
    angle_gz_max: CriterionVerdict,
    gm_0: CriterionVerdict,
    overall: CriterionVerdict,
    values: struct {
        area_0_30: f64,
        area_0_40: f64,
        area_30_40: f64,
        gz_at_30: f64,
        angle_gz_max_deg: f64,
        gm_0: f64,
    },
};

/// Assumption / validity flags attached to any workflow output.
pub const ValidityFlag = enum {
    wall_sided_assumption_valid,
    free_surface_applied,
    small_angle_regime,
    outside_validity_envelope,
    data_insufficient,
};

pub const ValidityFlags = std.EnumSet(ValidityFlag);

/// Proof level inherited from module documentation.
pub const ProofLevel = enum {
    unit_tested,
    cross_validated,
    benchmark_hull,
    model_test,
    class_society,
};

/// Explicit non-goals for regulatory / class-society workflows.
pub const RegulatoryExclusion = enum {
    not_class_approval,
    not_statutory_certificate,
    not_full_rulebook,
    not_operational_waiver,
    kernel_only,
};

pub const RegulatoryExclusions = std.EnumSet(RegulatoryExclusion);

/// Bundle attached to regulatory compose outputs — what this result is NOT.
pub const RegulatoryBoundary = struct {
    exclusions: RegulatoryExclusions,
    proof_level: ProofLevel = .unit_tested,
    disclaimer: []const u8 = "Computational kernel output; not a class-society submission.",

    pub fn defaultKernel() RegulatoryBoundary {
        var ex: RegulatoryExclusions = .{};
        ex.insert(.not_class_approval);
        ex.insert(.not_statutory_certificate);
        ex.insert(.not_full_rulebook);
        ex.insert(.kernel_only);
        return .{ .exclusions = ex };
    }
};

test "RegulatoryBoundary defaults exclude class approval" {
    const b = RegulatoryBoundary.defaultKernel();
    try std.testing.expect(b.exclusions.contains(.not_class_approval));
    try std.testing.expect(b.exclusions.contains(.kernel_only));
}

test "PrincipalParticulars ratios" {
    const p: PrincipalParticulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 };
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), p.lOverB(), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0 / 3.0), p.bOverT(), 1e-12);
}