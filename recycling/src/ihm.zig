const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    UnknownMaterial,
    UnequalLength,
};

/// HKC Appendix 1 hazardous materials prohibited or restricted on
/// ships' new installations (after entry into force).
pub const HazardousMaterial = enum {
    asbestos, // App. 1 prohibited
    pcb, // App. 1 prohibited
    ods, // App. 1 phased out
    anti_fouling_TBT, // App. 1 prohibited
    cadmium, // App. 2 max 0.01%
    hexavalent_chromium, // App. 2 max 0.1%
    lead, // App. 2 max 0.1%
    mercury, // App. 2 max 0.1%
    pbb, // App. 2 max 0.1% (Polybrominated biphenyl)
    pbde, // App. 2 max 0.1% (Polybrominated diphenyl ether)
    pfos, // App. 2 prohibited (PFOS)
    short_chain_paraffins, // App. 2 max 1%

    /// HKC max-allowable mass fraction (kg material / kg article).
    /// 0 indicates prohibited / not allowed; small positive is the
    /// concentration ceiling.
    pub fn maxAllowableFraction(self: HazardousMaterial) f64 {
        return switch (self) {
            .asbestos => 0.0,
            .pcb => 0.0,
            .ods => 0.0,
            .anti_fouling_TBT => 0.0,
            .cadmium => 0.0001,
            .hexavalent_chromium => 0.001,
            .lead => 0.001,
            .mercury => 0.001,
            .pbb => 0.001,
            .pbde => 0.001,
            .pfos => 0.0,
            .short_chain_paraffins => 0.01,
        };
    }
};

/// Per-material entry in the IHM Part I (materials in ship structure
/// and equipment).
pub const IHMEntry = struct {
    material: HazardousMaterial,
    mass_kg: f64,
    host_article_mass_kg: f64,
};

/// Concentration of a material within its host article.
pub fn concentrationFraction(entry: IHMEntry) Error!f64 {
    if (!(entry.mass_kg >= 0)) return Error.NonPositiveMass;
    if (!(entry.host_article_mass_kg > 0)) return Error.NonPositiveMass;
    return entry.mass_kg / entry.host_article_mass_kg;
}

pub const Verdict = enum { pass, fail };

/// Per-entry verdict: concentration <= the HKC maximum.
pub fn entryVerdict(entry: IHMEntry) Error!Verdict {
    const c = try concentrationFraction(entry);
    const max = entry.material.maxAllowableFraction();
    if (c <= max) return .pass;
    return .fail;
}

/// Total mass of all entries.
pub fn totalIHMMassKg(entries: []const IHMEntry) Error!f64 {
    var sum: f64 = 0.0;
    for (entries) |e| {
        if (!(e.mass_kg >= 0)) return Error.NonPositiveMass;
        sum += e.mass_kg;
    }
    return sum;
}

/// Count of failing entries.
pub fn failingEntryCount(entries: []const IHMEntry) Error!usize {
    var n: usize = 0;
    for (entries) |e| {
        const v = try entryVerdict(e);
        if (v == .fail) n += 1;
    }
    return n;
}

test "asbestos prohibited (max fraction 0)" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), HazardousMaterial.asbestos.maxAllowableFraction(), 1e-12);
}

test "cadmium max fraction 0.01% = 0.0001" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0001), HazardousMaterial.cadmium.maxAllowableFraction(), 1e-15);
}

test "short-chain paraffins max 1%" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), HazardousMaterial.short_chain_paraffins.maxAllowableFraction(), 1e-12);
}

test "concentration fraction: 1 kg lead in 1000 kg paint = 0.001" {
    const e: IHMEntry = .{
        .material = .lead,
        .mass_kg = 1.0,
        .host_article_mass_kg = 1000.0,
    };
    try std.testing.expectApproxEqAbs(@as(f64, 0.001), try concentrationFraction(e), 1e-12);
}

test "lead at exactly 0.1% concentration passes" {
    const e: IHMEntry = .{
        .material = .lead,
        .mass_kg = 1.0,
        .host_article_mass_kg = 1000.0,
    };
    try std.testing.expectEqual(Verdict.pass, try entryVerdict(e));
}

test "lead at 0.2% concentration fails" {
    const e: IHMEntry = .{
        .material = .lead,
        .mass_kg = 2.0,
        .host_article_mass_kg = 1000.0,
    };
    try std.testing.expectEqual(Verdict.fail, try entryVerdict(e));
}

test "any asbestos fails (prohibited)" {
    const e: IHMEntry = .{
        .material = .asbestos,
        .mass_kg = 0.001,
        .host_article_mass_kg = 1000.0,
    };
    try std.testing.expectEqual(Verdict.fail, try entryVerdict(e));
}

test "zero asbestos passes" {
    const e: IHMEntry = .{
        .material = .asbestos,
        .mass_kg = 0.0,
        .host_article_mass_kg = 1000.0,
    };
    try std.testing.expectEqual(Verdict.pass, try entryVerdict(e));
}

test "totalIHMMassKg sums entries" {
    const entries = [_]IHMEntry{
        .{ .material = .lead, .mass_kg = 10.0, .host_article_mass_kg = 10_000.0 },
        .{ .material = .mercury, .mass_kg = 0.5, .host_article_mass_kg = 5000.0 },
    };
    const total = try totalIHMMassKg(&entries);
    try std.testing.expectApproxEqAbs(@as(f64, 10.5), total, 1e-9);
}

test "failingEntryCount detects multiple failures" {
    const entries = [_]IHMEntry{
        .{ .material = .lead, .mass_kg = 5.0, .host_article_mass_kg = 1000.0 }, // 0.5% -> fail
        .{ .material = .lead, .mass_kg = 1.0, .host_article_mass_kg = 1000.0 }, // 0.1% -> pass
        .{ .material = .asbestos, .mass_kg = 0.1, .host_article_mass_kg = 1000.0 }, // fail
    };
    try std.testing.expectEqual(@as(usize, 2), try failingEntryCount(&entries));
}

test "failingEntryCount returns 0 for clean inventory" {
    const entries = [_]IHMEntry{
        .{ .material = .lead, .mass_kg = 0.5, .host_article_mass_kg = 1000.0 },
        .{ .material = .mercury, .mass_kg = 0.1, .host_article_mass_kg = 1000.0 },
    };
    try std.testing.expectEqual(@as(usize, 0), try failingEntryCount(&entries));
}

test "input rejection: zero host article mass" {
    const e: IHMEntry = .{
        .material = .lead,
        .mass_kg = 1.0,
        .host_article_mass_kg = 0.0,
    };
    try std.testing.expectError(Error.NonPositiveMass, concentrationFraction(e));
}
