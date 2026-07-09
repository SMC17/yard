//! Evans Ship Design Spiral composition workflow.
//! Thin wrapper over yard-spiral with naval-arch validity flags.

const std = @import("std");
const naval = @import("yard_naval_arch");
const spiral = @import("yard_spiral");

pub const Error = error{
    SpiralFailed,
    OutOfMemory,
};

pub const Input = struct {
    design: spiral.orchestrator.DesignParameters,
    max_loops: u32 = 3,
    fidelity: spiral.stages.Fidelity = .mid,
    gm_min_m: f64 = 0.5,
};

pub const Output = struct {
    result: spiral.orchestrator.SpiralResult,
    objective_score: f64,
    flags: naval.ValidityFlags,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn evaluate(allocator: std.mem.Allocator, input: Input) Error!Output {
    const orch = spiral.orchestrator.Orchestrator.init(allocator, input.max_loops, input.fidelity);
    const result = orch.runSpiral(input.design) catch return Error.SpiralFailed;

    var flags: naval.ValidityFlags = .{};
    if (result.final.gm_m >= input.gm_min_m) flags.insert(.wall_sided_assumption_valid);
    if (result.converged) flags.insert(.small_angle_regime);

    const score = spiral.orchestrator.evaluateObjective(result.final, input.gm_min_m);

    return .{
        .result = result,
        .objective_score = score,
        .flags = flags,
    };
}

pub fn freeOutput(allocator: std.mem.Allocator, output: *Output) void {
    var orch = spiral.orchestrator.Orchestrator.init(allocator, 1, .low);
    orch.freeSpiralResult(&output.result);
}

test "design spiral mid-fidelity cargo hull" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var out = try evaluate(arena.allocator(), .{
        .design = .{
            .length = 100.0,
            .beam = 16.0,
            .draft = 6.0,
            .displacement = 0.0,
            .kg = 5.0,
            .service_speed = 8.0,
        },
        .max_loops = 2,
        .fidelity = .mid,
    });
    defer freeOutput(arena.allocator(), &out);

    try std.testing.expect(out.result.final.estimated_power_kw > 0.0);
    try std.testing.expect(out.objective_score > 0.0);
}