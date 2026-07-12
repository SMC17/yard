//! Class-neutral preliminary plate, stiffener, and hull-girder screening.
//!
//! These checks expose equations and utilization ratios for early design. They
//! are not a substitute for an applicable class society rule set or approval.

const std = @import("std");

pub const Material = struct {
    yield_strength_pa: f64,
    elastic_modulus_pa: f64,
    density_kg_m3: f64,
    allowable_stress_factor: f64 = 1.5,

    pub const mild_steel: Material = .{
        .yield_strength_pa = 235.0e6,
        .elastic_modulus_pa = 200.0e9,
        .density_kg_m3 = 7850.0,
    };
};

pub const Plate = struct {
    actual_thickness_m: f64,
    unsupported_width_m: f64,
    corrosion_allowance_m: f64,
};

pub const Stiffener = struct {
    actual_section_modulus_m3: f64,
    spacing_m: f64,
    unsupported_span_m: f64,
};

pub const Scantlings = struct {
    bottom: Plate,
    side: Plate,
    deck: Plate,
    longitudinal_stiffener: Stiffener,
    gross_hull_section_modulus_m3: f64,
    hull_section_corrosion_deduction_m3: f64,
};

pub const LoadCase = struct {
    name: []const u8,
    bottom_pressure_pa: f64,
    side_pressure_pa: f64,
    deck_pressure_pa: f64,
    stiffener_pressure_pa: f64,
    still_water_bending_moment_nm: f64,
    wave_bending_moment_nm: f64,
};

pub const ComponentResult = struct {
    required: f64,
    available: f64,
    utilization: f64,

    pub fn passes(self: ComponentResult) bool {
        return self.utilization <= 1.0;
    }
};

pub const Report = struct {
    load_case_name: []const u8,
    allowable_stress_pa: f64,
    bottom_plate: ComponentResult,
    side_plate: ComponentResult,
    deck_plate: ComponentResult,
    longitudinal_stiffener: ComponentResult,
    hull_girder: ComponentResult,
    governing_utilization: f64,

    pub fn passes(self: Report) bool {
        return self.governing_utilization <= 1.0;
    }
};

pub const Error = error{
    InvalidMaterial,
    InvalidPlate,
    InvalidStiffener,
    InvalidHullSection,
    InvalidLoad,
};

fn allowableStress(material: Material) Error!f64 {
    if (!std.math.isFinite(material.yield_strength_pa) or
        !std.math.isFinite(material.elastic_modulus_pa) or
        !std.math.isFinite(material.density_kg_m3) or
        !std.math.isFinite(material.allowable_stress_factor) or
        material.yield_strength_pa <= 0.0 or material.elastic_modulus_pa <= 0.0 or
        material.density_kg_m3 <= 0.0 or material.allowable_stress_factor < 1.0)
    {
        return Error.InvalidMaterial;
    }
    return material.yield_strength_pa / material.allowable_stress_factor;
}

fn checkPlate(plate: Plate, pressure_pa: f64, sigma_allow_pa: f64) Error!ComponentResult {
    if (!std.math.isFinite(plate.actual_thickness_m) or
        !std.math.isFinite(plate.unsupported_width_m) or
        !std.math.isFinite(plate.corrosion_allowance_m) or
        plate.actual_thickness_m <= 0.0 or plate.unsupported_width_m <= 0.0 or
        plate.corrosion_allowance_m < 0.0 or
        plate.corrosion_allowance_m >= plate.actual_thickness_m)
    {
        return Error.InvalidPlate;
    }
    if (!std.math.isFinite(pressure_pa) or pressure_pa < 0.0) return Error.InvalidLoad;

    // Unit-width simply-supported strip screening:
    // sigma ~= 0.75 p s^2 / t_net^2.
    const required_net = plate.unsupported_width_m * @sqrt(0.75 * pressure_pa / sigma_allow_pa);
    const required_gross = required_net + plate.corrosion_allowance_m;
    return .{
        .required = required_gross,
        .available = plate.actual_thickness_m,
        .utilization = required_gross / plate.actual_thickness_m,
    };
}

fn checkStiffener(stiffener: Stiffener, pressure_pa: f64, sigma_allow_pa: f64) Error!ComponentResult {
    if (!std.math.isFinite(stiffener.actual_section_modulus_m3) or
        !std.math.isFinite(stiffener.spacing_m) or
        !std.math.isFinite(stiffener.unsupported_span_m) or
        stiffener.actual_section_modulus_m3 <= 0.0 or stiffener.spacing_m <= 0.0 or
        stiffener.unsupported_span_m <= 0.0)
    {
        return Error.InvalidStiffener;
    }
    if (!std.math.isFinite(pressure_pa) or pressure_pa < 0.0) return Error.InvalidLoad;

    // Simply-supported beam under uniform line load w = p * spacing:
    // M_max = w L^2 / 8; Z_required = M_max / sigma_allow.
    const line_load_n_m = pressure_pa * stiffener.spacing_m;
    const required_z = line_load_n_m * stiffener.unsupported_span_m *
        stiffener.unsupported_span_m / (8.0 * sigma_allow_pa);
    return .{
        .required = required_z,
        .available = stiffener.actual_section_modulus_m3,
        .utilization = required_z / stiffener.actual_section_modulus_m3,
    };
}

fn checkHullGirder(scantlings: Scantlings, load: LoadCase, sigma_allow_pa: f64) Error!ComponentResult {
    if (!std.math.isFinite(scantlings.gross_hull_section_modulus_m3) or
        !std.math.isFinite(scantlings.hull_section_corrosion_deduction_m3) or
        scantlings.gross_hull_section_modulus_m3 <= 0.0 or
        scantlings.hull_section_corrosion_deduction_m3 < 0.0 or
        scantlings.hull_section_corrosion_deduction_m3 >= scantlings.gross_hull_section_modulus_m3)
    {
        return Error.InvalidHullSection;
    }
    if (!std.math.isFinite(load.still_water_bending_moment_nm) or
        !std.math.isFinite(load.wave_bending_moment_nm))
    {
        return Error.InvalidLoad;
    }
    const required_z = @abs(load.still_water_bending_moment_nm + load.wave_bending_moment_nm) /
        sigma_allow_pa;
    const available_z = scantlings.gross_hull_section_modulus_m3 -
        scantlings.hull_section_corrosion_deduction_m3;
    return .{
        .required = required_z,
        .available = available_z,
        .utilization = required_z / available_z,
    };
}

pub fn evaluate(scantlings: Scantlings, material: Material, load: LoadCase) Error!Report {
    if (load.name.len == 0) return Error.InvalidLoad;
    const sigma_allow = try allowableStress(material);
    const bottom = try checkPlate(scantlings.bottom, load.bottom_pressure_pa, sigma_allow);
    const side = try checkPlate(scantlings.side, load.side_pressure_pa, sigma_allow);
    const deck = try checkPlate(scantlings.deck, load.deck_pressure_pa, sigma_allow);
    const stiffener = try checkStiffener(scantlings.longitudinal_stiffener, load.stiffener_pressure_pa, sigma_allow);
    const hull_girder = try checkHullGirder(scantlings, load, sigma_allow);
    const governing = @max(
        @max(bottom.utilization, side.utilization),
        @max(@max(deck.utilization, stiffener.utilization), hull_girder.utilization),
    );
    return .{
        .load_case_name = load.name,
        .allowable_stress_pa = sigma_allow,
        .bottom_plate = bottom,
        .side_plate = side,
        .deck_plate = deck,
        .longitudinal_stiffener = stiffener,
        .hull_girder = hull_girder,
        .governing_utilization = governing,
    };
}

fn generousScantlings() Scantlings {
    const plate: Plate = .{
        .actual_thickness_m = 0.030,
        .unsupported_width_m = 0.60,
        .corrosion_allowance_m = 0.002,
    };
    return .{
        .bottom = plate,
        .side = plate,
        .deck = plate,
        .longitudinal_stiffener = .{
            .actual_section_modulus_m3 = 0.005,
            .spacing_m = 0.60,
            .unsupported_span_m = 2.5,
        },
        .gross_hull_section_modulus_m3 = 20.0,
        .hull_section_corrosion_deduction_m3 = 0.5,
    };
}

fn harborLoad() LoadCase {
    return .{
        .name = "screening-load",
        .bottom_pressure_pa = 60_000.0,
        .side_pressure_pa = 45_000.0,
        .deck_pressure_pa = 25_000.0,
        .stiffener_pressure_pa = 60_000.0,
        .still_water_bending_moment_nm = 0.8e9,
        .wave_bending_moment_nm = 0.7e9,
    };
}

test "scantling screen reports transparent component utilizations" {
    const report = try evaluate(generousScantlings(), .mild_steel, harborLoad());
    try std.testing.expect(report.passes());
    try std.testing.expect(report.bottom_plate.required > 0.0);
    try std.testing.expect(report.longitudinal_stiffener.required > 0.0);
    try std.testing.expect(report.hull_girder.required > 0.0);
    try std.testing.expect(report.governing_utilization >= report.deck_plate.utilization);
}

test "under-thickness is a hard failure" {
    var scantlings = generousScantlings();
    scantlings.bottom.actual_thickness_m = 0.004;
    const report = try evaluate(scantlings, .mild_steel, harborLoad());
    try std.testing.expect(!report.bottom_plate.passes());
    try std.testing.expect(!report.passes());
}

test "corrosion cannot consume the gross plate" {
    var scantlings = generousScantlings();
    scantlings.deck.corrosion_allowance_m = scantlings.deck.actual_thickness_m;
    try std.testing.expectError(Error.InvalidPlate, evaluate(scantlings, .mild_steel, harborLoad()));
}
