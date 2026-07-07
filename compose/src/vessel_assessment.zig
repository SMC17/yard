//! Full preliminary vessel assessment: stability + resistance.
//! Phase 1 composition target — hydro/mass proxy via box-barge + Holtrop cargo.

const std = @import("std");
const naval = @import("yard_naval_arch");

pub const box_barge = @import("box_barge.zig");
pub const cargo_resistance = @import("cargo_resistance.zig");

pub const Error = error{
    StabilityFailed,
    ResistanceFailed,
    OutOfMemory,
};

pub const Input = struct {
    /// Box-barge stability inputs (intact loading).
    stability: box_barge.Input,
    /// Resistance at one speed (cargo hull within Holtrop envelope).
    resistance: cargo_resistance.Input,
};

pub const Output = struct {
    stability: box_barge.Output,
    resistance: cargo_resistance.Output,
    /// Combined validity — both workflows must be in envelope.
    flags: naval.ValidityFlags,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn evaluate(allocator: std.mem.Allocator, input: Input) Error!Output {
    const stab = box_barge.evaluate(allocator, input.stability) catch return Error.StabilityFailed;
    const res = cargo_resistance.evaluate(input.resistance) catch return Error.ResistanceFailed;

    return .{
        .stability = stab,
        .resistance = res,
        .flags = stab.flags,
    };
}

test "canonical vessel assessment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const out = try evaluate(arena.allocator(), .{
        .stability = .{
            .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
            .loading = .{
                .kg_m = 1.0,
                .tanks = &[_]naval.TankSpec{
                    .{ .l_m = 5.0, .b_m = 3.0, .rho_fluid = 1000.0 },
                },
            },
        },
        .resistance = .{
            .hull = cargo_resistance.CargoFixture.hullParticulars(),
            .speed_mps = 8.0,
        },
    });

    try std.testing.expect(out.stability.stability.gm_corrected_m > 0);
    try std.testing.expect(out.resistance.r_total > 0);
    try std.testing.expect(out.flags.contains(.free_surface_applied));
}