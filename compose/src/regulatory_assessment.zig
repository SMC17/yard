//! Regulatory kernel bundle: CSR + STIR + CII with explicit non-approval boundary.
//! Computes numbers only — never a class-society or statutory certificate.

const std = @import("std");
const naval = @import("yard_naval_arch");
const csr = @import("yard_csr");
const stir = @import("yard_stir");
const cii = @import("yard_cii");

pub const Error = error{
    AssessmentFailed,
};

pub const CsrInput = struct {
    condition: csr.section_check.LoadingCondition,
    section: csr.section_check.Section,
};

pub const StirInput = struct {
    M_wind_nm: f64,
    displacement_kg: f64,
    GM_m: f64,
    phi_m_rad: f64,
    phi_F_rad: f64,
};

pub const CiiInput = struct {
    fuels: []const cii.cii.FuelEntry,
    dwt_t: f64,
    distance_nm: f64,
    baseline_gco2_per_tnm: f64,
    year: u16,
};

pub const Input = struct {
    csr: ?CsrInput = null,
    stir: ?StirInput = null,
    cii: ?CiiInput = null,
};

pub const Output = struct {
    csr_pass: ?bool = null,
    stir_pass: ?bool = null,
    cii_rating: ?cii.cii.Rating = null,
    attained_aer: ?f64 = null,
    boundary: naval.RegulatoryBoundary,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn evaluate(input: Input) Error!Output {
    var out: Output = .{
        .boundary = naval.RegulatoryBoundary.defaultKernel(),
    };

    if (input.csr) |c| {
        const r = csr.section_check.evaluate(c.condition, c.section) catch return Error.AssessmentFailed;
        out.csr_pass = r.overall == .pass;
    }

    if (input.stir) |s| {
        const phi_0 = stir.dead_ship.staticHeelAngleSmallAngleRad(s.M_wind_nm, s.displacement_kg, s.GM_m, 9.80665) catch
            return Error.AssessmentFailed;
        const phi_1 = stir.dead_ship.residualRollAngleRad(phi_0, s.phi_m_rad) catch return Error.AssessmentFailed;
        out.stir_pass = stir.dead_ship.verdict(phi_1, s.phi_F_rad) == .pass;
    }

    if (input.cii) |c| {
        const aer = cii.cii.attainedAERgCO2PerTNm(c.fuels, c.dwt_t, c.distance_nm) catch return Error.AssessmentFailed;
        const req = cii.cii.requiredCIIgCO2PerTNm(c.baseline_gco2_per_tnm, c.year) catch return Error.AssessmentFailed;
        out.attained_aer = aer;
        out.cii_rating = cii.cii.classifyBulkCarrier(aer, req);
    }

    return out;
}

test "regulatory bundle attaches kernel-only boundary" {
    const out = try evaluate(.{
        .stir = .{
            .M_wind_nm = 5.0e5,
            .displacement_kg = 8.0e6,
            .GM_m = 1.2,
            .phi_m_rad = 0.15,
            .phi_F_rad = 0.45,
        },
    });
    try std.testing.expect(out.boundary.exclusions.contains(.not_class_approval));
    try std.testing.expect(out.stir_pass != null);
}