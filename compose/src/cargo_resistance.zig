//! Cargo hull resistance workflow: Holtrop-Mennen 1984 + ITTC-57.
//! Wires resistance/holtrop + resistance/ittc57 with naval-arch types.

const std = @import("std");
const resistance = @import("yard_resistance");
const naval = @import("yard_naval_arch");

pub const Error = error{
    ResistanceComputationFailed,
    OutsideValidityEnvelope,
};

/// Representative single-screw cargo within Holtrop 1984 validity envelope.
pub const CargoFixture = struct {
    pub fn hullParticulars() resistance.holtrop.HullParticulars {
        return .{
            .L = 100.0,
            .B = 16.0,
            .T = 6.0,
            .displacement_vol = 8500.0,
            .S = 2500.0,
            .C_B = 0.65,
            .C_M = 0.98,
            .C_P = 0.66,
            .C_WP = 0.78,
            .lcb_pct = -1.0,
            .c_stern = 0.0,
        };
    }
};

pub const Input = struct {
    hull: resistance.holtrop.HullParticulars,
    speed_mps: f64,
    env: resistance.holtrop.Environment = .{},
};

pub const Output = struct {
    speed_mps: f64,
    reynolds: f64,
    froude: f64,
    c_f: f64,
    form_factor: f64,
    r_friction: f64,
    r_wave: f64,
    r_total: f64,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn evaluate(input: Input) Error!Output {
    // Validity envelope check (Holtrop 1984 aggregate ranges).
    const hp = input.hull;
    const lb = hp.L / hp.B;
    const bt = hp.B / hp.T;
    if (lb < 3.9 or lb > 14.9 or bt < 2.1 or bt > 4.0 or
        hp.C_B < 0.55 or hp.C_B > 0.85 or
        hp.C_P < 0.55 or hp.C_P > 0.85)
    {
        return Error.OutsideValidityEnvelope;
    }

    const breakdown = resistance.holtrop.totalResistance(hp, input.speed_mps, input.env) catch
        return Error.ResistanceComputationFailed;

    return .{
        .speed_mps = input.speed_mps,
        .reynolds = breakdown.rn,
        .froude = breakdown.fn_val,
        .c_f = breakdown.c_f,
        .form_factor = breakdown.one_plus_k,
        .r_friction = breakdown.r_f,
        .r_wave = breakdown.r_w,
        .r_total = breakdown.r_total,
    };
}

test "cargo fixture resistance at 8 m/s" {
    const out = try evaluate(.{
        .hull = CargoFixture.hullParticulars(),
        .speed_mps = 8.0,
    });
    try std.testing.expect(out.r_total > 0.0);
    try std.testing.expect(out.form_factor > 1.05);
    try std.testing.expect(out.froude > 0.2 and out.froude < 0.3);
    // Fn = 8 / sqrt(9.81 * 100) ≈ 0.256
    try std.testing.expectApproxEqAbs(@as(f64, 0.2557), out.froude, 0.01);
}