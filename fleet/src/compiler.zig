//! Multi-vessel design compiler: deterministic validation and derivation.

const std = @import("std");
const design = @import("design.zig");
const scantlings = @import("scantlings.zig");

pub const Candidate = struct {
    spec: design.Spec,
    material: scantlings.Material,
    structure: scantlings.Scantlings,
    load_cases: []const scantlings.LoadCase,
};

pub const CompiledVessel = struct {
    spec: design.Spec,
    envelope: design.EnvelopeReport,
    derived: design.Derived,
    governing_scantling: scantlings.Report,
    load_cases_checked: usize,
};

pub const Compilation = struct {
    allocator: std.mem.Allocator,
    vessels: []CompiledVessel,

    pub fn deinit(self: *Compilation) void {
        self.allocator.free(self.vessels);
        self.* = undefined;
    }
};

pub const Error = error{
    EmptyFleet,
    EmptyLoadCases,
    DuplicateId,
    ScantlingFailure,
};

fn compileOne(candidate: Candidate) !CompiledVessel {
    if (candidate.load_cases.len == 0) return Error.EmptyLoadCases;
    const envelope = try design.checkEnvelope(candidate.spec);
    const derived = try design.derive(candidate.spec);
    var governing = try scantlings.evaluate(candidate.structure, candidate.material, candidate.load_cases[0]);
    for (candidate.load_cases[1..]) |load| {
        const report = try scantlings.evaluate(candidate.structure, candidate.material, load);
        if (report.governing_utilization > governing.governing_utilization) governing = report;
    }
    if (!governing.passes()) return Error.ScantlingFailure;
    return .{
        .spec = candidate.spec,
        .envelope = envelope,
        .derived = derived,
        .governing_scantling = governing,
        .load_cases_checked = candidate.load_cases.len,
    };
}

pub fn compileFleet(allocator: std.mem.Allocator, candidates: []const Candidate) !Compilation {
    if (candidates.len == 0) return Error.EmptyFleet;
    for (candidates, 0..) |candidate, index| {
        for (candidates[0..index]) |previous| {
            if (std.mem.eql(u8, candidate.spec.id, previous.spec.id)) return Error.DuplicateId;
        }
    }

    const vessels = try allocator.alloc(CompiledVessel, candidates.len);
    errdefer allocator.free(vessels);
    for (candidates, 0..) |candidate, index| vessels[index] = try compileOne(candidate);
    return .{ .allocator = allocator, .vessels = vessels };
}

fn specFor(id: []const u8, archetype: design.Archetype) design.Spec {
    var spec: design.Spec = switch (archetype) {
        .large_deck_carrier => .{
            .id = id,
            .archetype = archetype,
            .length_m = 260.0,
            .beam_m = 40.0,
            .draft_m = 11.0,
            .block_coefficient = 0.58,
            .waterplane_coefficient = 0.78,
            .declared_displacement_t = 1.0,
            .service_speed_m_s = 13.0,
            .installed_power_kw = 120_000.0,
            .kg_m = 14.0,
            .transverse_gm_m = 2.5,
            .longitudinal_gm_m = 230.0,
        },
        .cruiser => .{
            .id = id,
            .archetype = archetype,
            .length_m = 180.0,
            .beam_m = 20.0,
            .draft_m = 7.0,
            .block_coefficient = 0.55,
            .waterplane_coefficient = 0.75,
            .declared_displacement_t = 1.0,
            .service_speed_m_s = 14.0,
            .installed_power_kw = 70_000.0,
            .kg_m = 9.0,
            .transverse_gm_m = 1.8,
            .longitudinal_gm_m = 160.0,
        },
        .destroyer => .{
            .id = id,
            .archetype = archetype,
            .length_m = 140.0,
            .beam_m = 16.0,
            .draft_m = 5.0,
            .block_coefficient = 0.50,
            .waterplane_coefficient = 0.73,
            .declared_displacement_t = 1.0,
            .service_speed_m_s = 14.0,
            .installed_power_kw = 45_000.0,
            .kg_m = 7.0,
            .transverse_gm_m = 1.5,
            .longitudinal_gm_m = 120.0,
        },
        .merchant => .{
            .id = id,
            .archetype = archetype,
            .length_m = 200.0,
            .beam_m = 32.0,
            .draft_m = 11.0,
            .block_coefficient = 0.80,
            .waterplane_coefficient = 0.86,
            .declared_displacement_t = 1.0,
            .service_speed_m_s = 8.0,
            .installed_power_kw = 14_000.0,
            .kg_m = 8.0,
            .transverse_gm_m = 2.0,
            .longitudinal_gm_m = 140.0,
        },
        .patrol => .{
            .id = id,
            .archetype = archetype,
            .length_m = 55.0,
            .beam_m = 8.0,
            .draft_m = 2.5,
            .block_coefficient = 0.55,
            .waterplane_coefficient = 0.72,
            .declared_displacement_t = 1.0,
            .service_speed_m_s = 12.0,
            .installed_power_kw = 8_000.0,
            .kg_m = 3.0,
            .transverse_gm_m = 1.0,
            .longitudinal_gm_m = 42.0,
        },
    };
    spec.declared_displacement_t = design.displacementFromGeometryT(spec);
    return spec;
}

fn safeStructure() scantlings.Scantlings {
    const plate: scantlings.Plate = .{
        .actual_thickness_m = 0.050,
        .unsupported_width_m = 0.50,
        .corrosion_allowance_m = 0.002,
    };
    return .{
        .bottom = plate,
        .side = plate,
        .deck = plate,
        .longitudinal_stiffener = .{
            .actual_section_modulus_m3 = 0.010,
            .spacing_m = 0.50,
            .unsupported_span_m = 2.0,
        },
        .gross_hull_section_modulus_m3 = 100.0,
        .hull_section_corrosion_deduction_m3 = 1.0,
    };
}

const test_loads = [_]scantlings.LoadCase{
    .{
        .name = "departure",
        .bottom_pressure_pa = 50_000.0,
        .side_pressure_pa = 40_000.0,
        .deck_pressure_pa = 25_000.0,
        .stiffener_pressure_pa = 50_000.0,
        .still_water_bending_moment_nm = 0.8e9,
        .wave_bending_moment_nm = 0.7e9,
    },
    .{
        .name = "arrival",
        .bottom_pressure_pa = 45_000.0,
        .side_pressure_pa = 35_000.0,
        .deck_pressure_pa = 30_000.0,
        .stiffener_pressure_pa = 45_000.0,
        .still_water_bending_moment_nm = -0.6e9,
        .wave_bending_moment_nm = -0.7e9,
    },
};

test "one compilation covers five generic vessel archetypes" {
    const archetypes = [_]design.Archetype{
        .large_deck_carrier, .cruiser, .destroyer, .merchant, .patrol,
    };
    const ids = [_][]const u8{ "deck-01", "cruiser-01", "destroyer-01", "merchant-01", "patrol-01" };
    var candidates: [5]Candidate = undefined;
    for (&candidates, 0..) |*candidate, i| candidate.* = .{
        .spec = specFor(ids[i], archetypes[i]),
        .material = .mild_steel,
        .structure = safeStructure(),
        .load_cases = &test_loads,
    };

    var compilation = try compileFleet(std.testing.allocator, &candidates);
    defer compilation.deinit();
    try std.testing.expectEqual(@as(usize, 5), compilation.vessels.len);
    for (compilation.vessels) |vessel| {
        try std.testing.expect(vessel.envelope.withinEnvelope());
        try std.testing.expect(vessel.governing_scantling.passes());
        try std.testing.expectEqual(@as(usize, 2), vessel.load_cases_checked);
        try std.testing.expect(vessel.derived.max_acceleration_m_s2 > 0.0);
    }
}

test "duplicate IDs and failed scantlings are rejected" {
    const first: Candidate = .{
        .spec = specFor("same", .merchant),
        .material = .mild_steel,
        .structure = safeStructure(),
        .load_cases = &test_loads,
    };
    const duplicates = [_]Candidate{ first, first };
    try std.testing.expectError(Error.DuplicateId, compileFleet(std.testing.allocator, &duplicates));

    var weak = first;
    weak.spec.id = "weak";
    weak.structure.bottom.actual_thickness_m = 0.003;
    try std.testing.expectError(Error.ScantlingFailure, compileFleet(std.testing.allocator, &.{weak}));
}
