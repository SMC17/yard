//! Era envelopes: which materials, propulsion, and dimensions a design may
//! use, and a checker that returns every violation (not just the first).

const std = @import("std");
const materials = @import("materials.zig");
const rules = @import("rules.zig");

pub const PropulsionKind = enum {
    sail,
    steam_reciprocating,
    steam_turbine,
    diesel,
    gas_turbine,
    electric,
    wind_assist,
};

pub const EraId = enum {
    age_of_sail, // 1650-1815
    clipper, // 1840-1875
    steam_transition, // 1860-1905
    dreadnought, // 1905-1922 (Washington Treaty closes it)
    ww2, // 1935-1950
    modern, // 1990-
};

pub const Envelope = struct {
    id: EraId,
    year_from: i32,
    year_to: i32,
    allowed_materials: []const materials.MaterialId,
    allowed_propulsion: []const PropulsionKind,
    max_loa_m: f64,
    max_beam_m: f64,
    max_draft_m: f64,
    /// Maximum L/D for the hull girder in this era's primary material.
    max_l_over_d: f64,
    /// Treaty displacement cap [t], 0 = uncapped.
    max_displacement_t: f64,
};

pub const envelopes = [_]Envelope{
    .{
        .id = .age_of_sail,
        .year_from = 1650,
        .year_to = 1815,
        .allowed_materials = &.{ .oak, .teak },
        .allowed_propulsion = &.{.sail},
        // HMS Victory: 69.3 m LOA, 15.8 m beam, 8.8 m draught. The biggest
        // wooden walls crowd these caps; they are era practice, not physics.
        .max_loa_m = 80.0,
        .max_beam_m = 17.0,
        .max_draft_m = 9.0,
        .max_l_over_d = 10.0,
        .max_displacement_t = 0,
    },
    .{
        .id = .clipper,
        .year_from = 1840,
        .year_to = 1875,
        .allowed_materials = &.{ .oak, .teak, .wrought_iron },
        .allowed_propulsion = &.{ .sail, .steam_reciprocating },
        // Great Republic (1853), largest wooden clipper: ~92 m.
        .max_loa_m = 95.0,
        .max_beam_m = 18.0,
        .max_draft_m = 9.0,
        .max_l_over_d = 12.0,
        .max_displacement_t = 0,
    },
    .{
        .id = .steam_transition,
        .year_from = 1860,
        .year_to = 1905,
        .allowed_materials = &.{ .oak, .teak, .wrought_iron, .riveted_steel },
        .allowed_propulsion = &.{ .sail, .steam_reciprocating },
        // Great Eastern (1858, wrought iron): 211 m — the era outlier.
        .max_loa_m = 215.0,
        .max_beam_m = 26.0,
        .max_draft_m = 10.0,
        .max_l_over_d = 13.0,
        .max_displacement_t = 0,
    },
    .{
        .id = .dreadnought,
        .year_from = 1905,
        .year_to = 1922,
        .allowed_materials = &.{.riveted_steel},
        .allowed_propulsion = &.{ .steam_reciprocating, .steam_turbine },
        .max_loa_m = 270.0,
        .max_beam_m = 33.0,
        .max_draft_m = 11.0,
        .max_l_over_d = 14.0,
        .max_displacement_t = 35_561.6, // Washington cap in metric tonnes
    },
    .{
        .id = .ww2,
        .year_from = 1935,
        .year_to = 1950,
        .allowed_materials = &.{ .riveted_steel, .mild_steel },
        .allowed_propulsion = &.{ .steam_reciprocating, .steam_turbine, .diesel },
        .max_loa_m = 300.0,
        .max_beam_m = 39.0,
        .max_draft_m = 12.0,
        .max_l_over_d = 14.0,
        .max_displacement_t = 0,
    },
    .{
        .id = .modern,
        .year_from = 1990,
        .year_to = 9999,
        .allowed_materials = &.{ .mild_steel, .ah36_steel },
        .allowed_propulsion = &.{ .diesel, .gas_turbine, .electric, .wind_assist, .sail },
        .max_loa_m = 400.0,
        .max_beam_m = 62.0,
        .max_draft_m = 17.0,
        .max_l_over_d = 15.0,
        .max_displacement_t = 0,
    },
};

pub fn get(id: EraId) Envelope {
    for (envelopes) |e| {
        if (e.id == id) return e;
    }
    unreachable;
}

pub const Design = struct {
    loa_m: f64,
    beam_m: f64,
    draft_m: f64,
    depth_m: f64,
    displacement_t: f64,
    material: materials.MaterialId,
    propulsion: PropulsionKind,
};

pub const Violation = enum {
    material_anachronistic,
    material_beyond_length_limit,
    propulsion_anachronistic,
    loa_exceeds_era,
    beam_exceeds_era,
    draft_exceeds_era,
    l_over_d_exceeds_era,
    displacement_exceeds_treaty,
};

pub const max_violations = @typeInfo(Violation).@"enum".fields.len;

/// Check a design against an era envelope. Returns all violations found,
/// written into `out` (size >= max_violations); the slice is the result.
pub fn check(envelope: Envelope, design: Design, out: []Violation) []Violation {
    std.debug.assert(out.len >= max_violations);
    var n: usize = 0;

    const material_allowed = for (envelope.allowed_materials) |m| {
        if (m == design.material) break true;
    } else false;
    if (!material_allowed) {
        out[n] = .material_anachronistic;
        n += 1;
    } else if (design.loa_m > materials.get(design.material).max_hull_length_m) {
        out[n] = .material_beyond_length_limit;
        n += 1;
    }

    const prop_allowed = for (envelope.allowed_propulsion) |p| {
        if (p == design.propulsion) break true;
    } else false;
    if (!prop_allowed) {
        out[n] = .propulsion_anachronistic;
        n += 1;
    }

    if (design.loa_m > envelope.max_loa_m) {
        out[n] = .loa_exceeds_era;
        n += 1;
    }
    if (design.beam_m > envelope.max_beam_m) {
        out[n] = .beam_exceeds_era;
        n += 1;
    }
    if (design.draft_m > envelope.max_draft_m) {
        out[n] = .draft_exceeds_era;
        n += 1;
    }
    if (design.depth_m > 0 and design.loa_m / design.depth_m > envelope.max_l_over_d) {
        out[n] = .l_over_d_exceeds_era;
        n += 1;
    }
    if (envelope.max_displacement_t > 0 and design.displacement_t > envelope.max_displacement_t) {
        out[n] = .displacement_exceeds_treaty;
        n += 1;
    }
    return out[0..n];
}

fn victory() Design {
    return .{
        .loa_m = 69.3,
        .beam_m = 15.8,
        .draft_m = 8.8,
        .depth_m = 13.0,
        .displacement_t = 3500.0,
        .material = .oak,
        .propulsion = .sail,
    };
}

test "HMS Victory passes the age-of-sail envelope" {
    var buf: [max_violations]Violation = undefined;
    const v = check(get(.age_of_sail), victory(), &buf);
    try std.testing.expectEqual(@as(usize, 0), v.len);
}

test "steel hull in the age of sail is anachronistic" {
    var buf: [max_violations]Violation = undefined;
    var d = victory();
    d.material = .mild_steel;
    const v = check(get(.age_of_sail), d, &buf);
    try std.testing.expectEqual(@as(usize, 1), v.len);
    try std.testing.expectEqual(Violation.material_anachronistic, v[0]);
}

test "200 m wooden hull violates both material and era limits" {
    var buf: [max_violations]Violation = undefined;
    var d = victory();
    d.loa_m = 200.0;
    d.depth_m = 20.0;
    const v = check(get(.age_of_sail), d, &buf);
    try std.testing.expect(v.len >= 2);
    try std.testing.expectEqual(Violation.material_beyond_length_limit, v[0]);
    try std.testing.expectEqual(Violation.loa_exceeds_era, v[1]);
}

test "diesel in the clipper era is anachronistic" {
    var buf: [max_violations]Violation = undefined;
    var d = victory();
    d.propulsion = .diesel;
    const v = check(get(.clipper), d, &buf);
    try std.testing.expectEqual(@as(usize, 1), v.len);
    try std.testing.expectEqual(Violation.propulsion_anachronistic, v[0]);
}

test "Washington Treaty cap binds in the dreadnought era" {
    var buf: [max_violations]Violation = undefined;
    const yamato_like: Design = .{
        .loa_m = 263.0,
        .beam_m = 32.9,
        .draft_m = 10.4,
        .depth_m = 18.9,
        .displacement_t = 64_000.0,
        .material = .riveted_steel,
        .propulsion = .steam_turbine,
    };
    const v = check(get(.dreadnought), yamato_like, &buf);
    try std.testing.expectEqual(@as(usize, 1), v.len);
    try std.testing.expectEqual(Violation.displacement_exceeds_treaty, v[0]);
}

test "a modern handysize passes the modern envelope" {
    var buf: [max_violations]Violation = undefined;
    const coaster: Design = .{
        .loa_m = 100.0,
        .beam_m = 16.0,
        .draft_m = 6.0,
        .depth_m = 9.0,
        .displacement_t = 8700.0,
        .material = .ah36_steel,
        .propulsion = .diesel,
    };
    const v = check(get(.modern), coaster, &buf);
    try std.testing.expectEqual(@as(usize, 0), v.len);
}
