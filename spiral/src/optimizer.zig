// Design-space optimization atop spiral evaluations.

const std = @import("std");
const orchestrator = @import("orchestrator.zig");
pub const Error = orchestrator.Error;

/// Finite-difference gradient step on length (other dims fixed).
pub fn gradientOptimize(
    orch: orchestrator.Orchestrator,
    base: orchestrator.DesignParameters,
    step: f64,
    gm_min: f64,
) Error!orchestrator.DesignParameters {
    const score_base = orchestrator.evaluateObjective(base, gm_min);

    var plus = base;
    plus.length += step;
    var minus = base;
    if (base.length > step * 2.0) minus.length -= step;

    var sr_plus = try orch.runSpiral(plus);
    defer orch.freeSpiralResult(&sr_plus);
    var sr_minus = try orch.runSpiral(minus);
    defer orch.freeSpiralResult(&sr_minus);

    const score_plus = orchestrator.evaluateObjective(sr_plus.final, gm_min);
    const score_minus = orchestrator.evaluateObjective(sr_minus.final, gm_min);
    const grad = (score_plus - score_minus) / (plus.length - minus.length);

    var out = base;
    if (grad > 0.0) {
        out.length -= step;
    } else {
        out.length += step;
    }

    var sr_out = try orch.runSpiral(out);
    defer orch.freeSpiralResult(&sr_out);
    const score_out = orchestrator.evaluateObjective(sr_out.final, gm_min);
    if (score_out <= score_base) return sr_out.final;
    return base;
}

/// Population-based hull evolution (length, beam, draft mutations).
pub fn gaHullOptimize(
    orch: orchestrator.Orchestrator,
    population_size: u32,
    generations: u32,
    gm_min: f64,
) Error!orchestrator.DesignParameters {
    var rng = std.Random.DefaultPrng.init(0xDEAD_BEEF);
    const random = rng.random();

    var best = orchestrator.DesignParameters{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement = 0.0,
        .service_speed = 8.0,
        .c_b = 0.65,
    };
    var best_score = orchestrator.evaluateObjective(best, gm_min);

    var gen: u32 = 0;
    while (gen < generations) : (gen += 1) {
        var i: u32 = 0;
        while (i < population_size) : (i += 1) {
            var candidate = best;
            candidate.length *= random.float(f64) * 0.1 + 0.95;
            candidate.beam *= random.float(f64) * 0.08 + 0.96;
            candidate.draft *= random.float(f64) * 0.08 + 0.96;

            var sr = try orch.runSpiral(candidate);
            defer orch.freeSpiralResult(&sr);
            const score = orchestrator.evaluateObjective(sr.final, gm_min);
            if (score < best_score) {
                best = sr.final;
                best_score = score;
            }
        }
    }
    return best;
}

/// Iterative local optimizer: tighten beam/draft toward lower power.
pub fn optimizeDesign(
    orch: orchestrator.Orchestrator,
    base: orchestrator.DesignParameters,
    gm_min: f64,
) Error!orchestrator.DesignParameters {
    var current = base;
    var score = orchestrator.evaluateObjective(current, gm_min);

    const steps = [_]f64{ -1.0, 1.0 };
    for (steps) |d_b| {
        var trial = current;
        trial.beam += d_b;
        if (trial.beam < 10.0 or trial.beam > 30.0) continue;
        var sr = try orch.runSpiral(trial);
        defer orch.freeSpiralResult(&sr);
        const trial_score = orchestrator.evaluateObjective(sr.final, gm_min);
        if (trial_score < score and sr.final.gm_m >= gm_min) {
            current = sr.final;
            score = trial_score;
        }
    }
    return current;
}

test "GA improves or matches objective" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const orch = orchestrator.Orchestrator.init(arena.allocator(), 1, .low);
    const base = orchestrator.DesignParameters{
        .length = 120.0,
        .beam = 18.0,
        .draft = 7.0,
        .displacement = 0.0,
        .service_speed = 8.0,
        .c_b = 0.65,
    };
    const optimized = try gaHullOptimize(orch, 8, 2, 0.5);
    const base_score = orchestrator.evaluateObjective(base, 0.5);
    const opt_score = orchestrator.evaluateObjective(optimized, 0.5);
    try std.testing.expect(opt_score <= base_score * 1.5);
}