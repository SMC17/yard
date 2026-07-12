//! Generic vessel design envelopes and derived linearized 6-DOF models.
//!
//! The archetypes are broad public engineering categories. They are not
//! replicas of named vessels and do not encode weapons, signatures, damage
//! vulnerability, or tactical performance.

const std = @import("std");
const fossen = @import("yard_fossen").fossen;

pub const rho_seawater_kg_m3: f64 = 1025.0;
pub const gravity_m_s2: f64 = 9.80665;

pub const Archetype = enum {
    large_deck_carrier,
    cruiser,
    destroyer,
    merchant,
    patrol,
};

pub const Limits = struct {
    length_min_m: f64,
    length_max_m: f64,
    length_beam_min: f64,
    length_beam_max: f64,
    beam_draft_min: f64,
    beam_draft_max: f64,
    block_coefficient_min: f64,
    block_coefficient_max: f64,
    froude_max: f64,
};

/// Broad sanity envelopes used to reject category mistakes during early design.
/// These are not class rules or platform-specific design data.
pub fn limitsFor(archetype: Archetype) Limits {
    return switch (archetype) {
        .large_deck_carrier => .{
            .length_min_m = 180.0,
            .length_max_m = 360.0,
            .length_beam_min = 4.5,
            .length_beam_max = 9.0,
            .beam_draft_min = 3.0,
            .beam_draft_max = 8.0,
            .block_coefficient_min = 0.48,
            .block_coefficient_max = 0.72,
            .froude_max = 0.38,
        },
        .cruiser => .{
            .length_min_m = 110.0,
            .length_max_m = 250.0,
            .length_beam_min = 6.0,
            .length_beam_max = 12.0,
            .beam_draft_min = 2.5,
            .beam_draft_max = 5.5,
            .block_coefficient_min = 0.45,
            .block_coefficient_max = 0.68,
            .froude_max = 0.45,
        },
        .destroyer => .{
            .length_min_m = 85.0,
            .length_max_m = 200.0,
            .length_beam_min = 6.5,
            .length_beam_max = 12.5,
            .beam_draft_min = 2.4,
            .beam_draft_max = 5.5,
            .block_coefficient_min = 0.42,
            .block_coefficient_max = 0.66,
            .froude_max = 0.52,
        },
        .merchant => .{
            .length_min_m = 60.0,
            .length_max_m = 420.0,
            .length_beam_min = 4.5,
            .length_beam_max = 10.0,
            .beam_draft_min = 2.0,
            .beam_draft_max = 4.5,
            .block_coefficient_min = 0.52,
            .block_coefficient_max = 0.90,
            .froude_max = 0.34,
        },
        .patrol => .{
            .length_min_m = 15.0,
            .length_max_m = 110.0,
            .length_beam_min = 4.0,
            .length_beam_max = 10.0,
            .beam_draft_min = 2.0,
            .beam_draft_max = 5.0,
            .block_coefficient_min = 0.38,
            .block_coefficient_max = 0.72,
            .froude_max = 0.80,
        },
    };
}

pub const Spec = struct {
    id: []const u8,
    archetype: Archetype,
    length_m: f64,
    beam_m: f64,
    draft_m: f64,
    block_coefficient: f64,
    waterplane_coefficient: f64,
    declared_displacement_t: f64,
    service_speed_m_s: f64,
    installed_power_kw: f64,
    kg_m: f64,
    transverse_gm_m: f64,
    longitudinal_gm_m: f64,
};

pub const EnvelopeViolations = packed struct(u8) {
    length: bool = false,
    length_beam: bool = false,
    beam_draft: bool = false,
    block_coefficient: bool = false,
    froude: bool = false,
    displacement_closure: bool = false,
    _padding: u2 = 0,

    pub fn any(self: EnvelopeViolations) bool {
        return @as(u8, @bitCast(self)) != 0;
    }
};

pub const EnvelopeReport = struct {
    length_beam: f64,
    beam_draft: f64,
    froude_number: f64,
    displacement_closure_fraction: f64,
    violations: EnvelopeViolations,

    pub fn withinEnvelope(self: EnvelopeReport) bool {
        return !self.violations.any();
    }
};

pub const Propulsor = struct {
    x_m: f64,
    y_m: f64,
    axis_rad: f64,
    max_continuous_thrust_n: f64,
};

pub const PropulsorLayout = struct {
    count: usize,
    units: [4]Propulsor,

    pub fn slice(self: *const PropulsorLayout) []const Propulsor {
        return self.units[0..self.count];
    }
};

pub const Derived = struct {
    displacement_kg: f64,
    displacement_volume_m3: f64,
    waterplane_area_m2: f64,
    froude_number: f64,
    fossen_parameters: fossen.Parameters,
    propulsors: PropulsorLayout,
    max_speed_m_s: f64,
    max_acceleration_m_s2: f64,
};

pub const Error = error{
    EmptyId,
    NonFiniteInput,
    NonPositiveDimension,
    InvalidCoefficient,
    InvalidStability,
    OutsideArchetypeEnvelope,
};

fn allFinite(spec: Spec) bool {
    return std.math.isFinite(spec.length_m) and
        std.math.isFinite(spec.beam_m) and
        std.math.isFinite(spec.draft_m) and
        std.math.isFinite(spec.block_coefficient) and
        std.math.isFinite(spec.waterplane_coefficient) and
        std.math.isFinite(spec.declared_displacement_t) and
        std.math.isFinite(spec.service_speed_m_s) and
        std.math.isFinite(spec.installed_power_kw) and
        std.math.isFinite(spec.kg_m) and
        std.math.isFinite(spec.transverse_gm_m) and
        std.math.isFinite(spec.longitudinal_gm_m);
}

pub fn validateInput(spec: Spec) Error!void {
    if (spec.id.len == 0) return Error.EmptyId;
    if (!allFinite(spec)) return Error.NonFiniteInput;
    if (spec.length_m <= 0.0 or spec.beam_m <= 0.0 or spec.draft_m <= 0.0 or
        spec.declared_displacement_t <= 0.0 or spec.service_speed_m_s <= 0.0 or
        spec.installed_power_kw <= 0.0)
    {
        return Error.NonPositiveDimension;
    }
    if (spec.block_coefficient <= 0.0 or spec.block_coefficient > 1.0 or
        spec.waterplane_coefficient <= 0.0 or spec.waterplane_coefficient > 1.0)
    {
        return Error.InvalidCoefficient;
    }
    if (spec.kg_m < 0.0 or spec.transverse_gm_m <= 0.0 or spec.longitudinal_gm_m <= 0.0) {
        return Error.InvalidStability;
    }
}

pub fn displacementFromGeometryT(spec: Spec) f64 {
    return rho_seawater_kg_m3 * spec.length_m * spec.beam_m * spec.draft_m *
        spec.block_coefficient / 1000.0;
}

pub fn checkEnvelope(spec: Spec) Error!EnvelopeReport {
    try validateInput(spec);
    const limits = limitsFor(spec.archetype);
    const length_beam = spec.length_m / spec.beam_m;
    const beam_draft = spec.beam_m / spec.draft_m;
    const froude = spec.service_speed_m_s / @sqrt(gravity_m_s2 * spec.length_m);
    const geometric_displacement_t = displacementFromGeometryT(spec);
    const closure = @abs(spec.declared_displacement_t - geometric_displacement_t) /
        geometric_displacement_t;

    return .{
        .length_beam = length_beam,
        .beam_draft = beam_draft,
        .froude_number = froude,
        .displacement_closure_fraction = closure,
        .violations = .{
            .length = spec.length_m < limits.length_min_m or spec.length_m > limits.length_max_m,
            .length_beam = length_beam < limits.length_beam_min or length_beam > limits.length_beam_max,
            .beam_draft = beam_draft < limits.beam_draft_min or beam_draft > limits.beam_draft_max,
            .block_coefficient = spec.block_coefficient < limits.block_coefficient_min or
                spec.block_coefficient > limits.block_coefficient_max,
            .froude = froude > limits.froude_max,
            .displacement_closure = closure > 0.05,
        },
    };
}

fn propulsorCount(archetype: Archetype) usize {
    return switch (archetype) {
        .large_deck_carrier => 4,
        .cruiser, .destroyer, .patrol => 2,
        .merchant => 1,
    };
}

fn makePropulsorLayout(spec: Spec) PropulsorLayout {
    const count = propulsorCount(spec.archetype);
    const total_thrust = 0.65 * spec.installed_power_kw * 1000.0 / spec.service_speed_m_s;
    const per_unit = total_thrust / @as(f64, @floatFromInt(count));
    const x = -0.45 * spec.length_m;
    const y_outer = 0.18 * spec.beam_m;
    var layout: PropulsorLayout = .{
        .count = count,
        .units = [_]Propulsor{.{
            .x_m = 0.0,
            .y_m = 0.0,
            .axis_rad = 0.0,
            .max_continuous_thrust_n = 0.0,
        }} ** 4,
    };
    for (0..count) |i| {
        const y = if (count == 1) 0.0 else if (i % 2 == 0) y_outer else -y_outer;
        layout.units[i] = .{
            .x_m = x,
            .y_m = y,
            .axis_rad = 0.0,
            .max_continuous_thrust_n = per_unit,
        };
    }
    return layout;
}

/// Derive a linearized Fossen model and generic propulsion layout.
/// The damping time constants and added-mass factors are screening defaults;
/// later fidelity levels should replace them with identified coefficients.
pub fn derive(spec: Spec) Error!Derived {
    const report = try checkEnvelope(spec);
    if (!report.withinEnvelope()) return Error.OutsideArchetypeEnvelope;

    const displacement_kg = spec.declared_displacement_t * 1000.0;
    const volume = displacement_kg / rho_seawater_kg_m3;
    const waterplane_area = spec.length_m * spec.beam_m * spec.waterplane_coefficient;
    const i_x = displacement_kg * (spec.beam_m * spec.beam_m + spec.draft_m * spec.draft_m) / 12.0;
    const i_y = displacement_kg * (spec.length_m * spec.length_m + spec.draft_m * spec.draft_m) / 12.0;
    const i_z = displacement_kg * (spec.length_m * spec.length_m + spec.beam_m * spec.beam_m) / 12.0;

    const m_diag: [6]f64 = .{
        1.05 * displacement_kg,
        1.30 * displacement_kg,
        1.45 * displacement_kg,
        1.12 * i_x,
        1.08 * i_y,
        1.10 * i_z,
    };
    const d_lin: [6]f64 = .{
        m_diag[0] / 80.0,
        m_diag[1] / 35.0,
        m_diag[2] / 18.0,
        m_diag[3] / 10.0,
        m_diag[4] / 14.0,
        m_diag[5] / 28.0,
    };
    const propulsors = makePropulsorLayout(spec);
    var total_thrust: f64 = 0.0;
    for (propulsors.slice()) |unit| total_thrust += unit.max_continuous_thrust_n;

    return .{
        .displacement_kg = displacement_kg,
        .displacement_volume_m3 = volume,
        .waterplane_area_m2 = waterplane_area,
        .froude_number = report.froude_number,
        .fossen_parameters = .{
            .M_diag = m_diag,
            .D_lin = d_lin,
            .K_z = rho_seawater_kg_m3 * gravity_m_s2 * waterplane_area,
            .K_phi = displacement_kg * gravity_m_s2 * spec.transverse_gm_m,
            .K_theta = displacement_kg * gravity_m_s2 * spec.longitudinal_gm_m,
        },
        .propulsors = propulsors,
        .max_speed_m_s = 1.15 * spec.service_speed_m_s,
        .max_acceleration_m_s2 = total_thrust / m_diag[0],
    };
}

fn merchantSpec() Spec {
    const base = Spec{
        .id = "merchant-01",
        .archetype = .merchant,
        .length_m = 200.0,
        .beam_m = 32.0,
        .draft_m = 11.0,
        .block_coefficient = 0.80,
        .waterplane_coefficient = 0.86,
        .declared_displacement_t = 0.0,
        .service_speed_m_s = 8.0,
        .installed_power_kw = 14_000.0,
        .kg_m = 8.0,
        .transverse_gm_m = 2.0,
        .longitudinal_gm_m = 140.0,
    };
    var spec = base;
    spec.declared_displacement_t = displacementFromGeometryT(spec);
    return spec;
}

test "merchant design closes displacement and derives positive 6-DOF terms" {
    const spec = merchantSpec();
    const report = try checkEnvelope(spec);
    try std.testing.expect(report.withinEnvelope());
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), report.displacement_closure_fraction, 1e-14);

    const result = try derive(spec);
    for (result.fossen_parameters.M_diag) |value| try std.testing.expect(value > 0.0);
    for (result.fossen_parameters.D_lin) |value| try std.testing.expect(value > 0.0);
    try std.testing.expect(result.fossen_parameters.K_phi > 0.0);
    try std.testing.expectEqual(@as(usize, 1), result.propulsors.count);
}

test "envelope rejects displacement that does not close" {
    var spec = merchantSpec();
    spec.declared_displacement_t *= 1.20;
    const report = try checkEnvelope(spec);
    try std.testing.expect(report.violations.displacement_closure);
    try std.testing.expectError(Error.OutsideArchetypeEnvelope, derive(spec));
}

test "input validation rejects NaN and invalid stability" {
    var spec = merchantSpec();
    spec.length_m = std.math.nan(f64);
    try std.testing.expectError(Error.NonFiniteInput, validateInput(spec));
    spec = merchantSpec();
    spec.transverse_gm_m = 0.0;
    try std.testing.expectError(Error.InvalidStability, validateInput(spec));
}
