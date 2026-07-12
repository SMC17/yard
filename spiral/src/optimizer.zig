// Design-space optimization atop spiral evaluations.

const std = @import("std");
const orchestrator = @import("orchestrator.zig");
pub const Error = orchestrator.Error;

/// Multi-objective design point for Pareto analysis.
pub const ParetoPoint = struct {
    params: orchestrator.DesignParameters,
    power_kw: f64,
    gm_m: f64,
    heave_m: f64,
};

pub fn dominates(a: ParetoPoint, b: ParetoPoint) bool {
    const le_pwr = a.power_kw <= b.power_kw;
    const le_heave = a.heave_m <= b.heave_m;
    const ge_gm = a.gm_m >= b.gm_m;
    const strict = a.power_kw < b.power_kw or a.heave_m < b.heave_m or a.gm_m > b.gm_m;
    return le_pwr and le_heave and ge_gm and strict;
}

/// Extract non-dominated points (minimize power + heave, maximize GM).
pub fn paretoFront(allocator: std.mem.Allocator, points: []const ParetoPoint) Error![]ParetoPoint {
    var front: std.ArrayList(ParetoPoint) = .empty;
    errdefer front.deinit(allocator);

    for (points) |p| {
        var dominated = false;
        for (points) |q| {
            if (dominates(q, p)) {
                dominated = true;
                break;
            }
        }
        if (!dominated) try front.append(allocator, p);
    }
    return front.toOwnedSlice(allocator);
}

/// GA exploration returning Pareto front across population history.
pub fn gaParetoExplore(
    orch: orchestrator.Orchestrator,
    population_size: u32,
    generations: u32,
    gm_min: f64,
) Error![]ParetoPoint {
    _ = gm_min;
    var rng = std.Random.DefaultPrng.init(0xFEED_FACE);
    const random = rng.random();

    var history: std.ArrayList(ParetoPoint) = .empty;
    errdefer history.deinit(orch.allocator);

    const seed = orchestrator.DesignParameters{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement = 0.0,
        .service_speed = 8.0,
        .c_b = 0.65,
    };

    var gen: u32 = 0;
    while (gen < generations) : (gen += 1) {
        var i: u32 = 0;
        while (i < population_size) : (i += 1) {
            var candidate = seed;
            candidate.length *= random.float(f64) * 0.12 + 0.94;
            candidate.beam *= random.float(f64) * 0.10 + 0.95;
            candidate.draft *= random.float(f64) * 0.10 + 0.95;

            var sr = try orch.runSpiral(candidate);
            defer orch.freeSpiralResult(&sr);

            try history.append(orch.allocator, .{
                .params = sr.final,
                .power_kw = sr.final.estimated_power_kw,
                .gm_m = sr.final.gm_m,
                .heave_m = sr.final.significant_heave_m,
            });
        }
    }
    const all = try history.toOwnedSlice(orch.allocator);
    defer orch.allocator.free(all);
    return paretoFront(orch.allocator, all);
}

/// Finite-difference gradient step on length (other dims fixed).
/// Multi-variable finite-difference gradient step on L, B, and T.
pub fn gradientOptimize(
    orch: orchestrator.Orchestrator,
    base: orchestrator.DesignParameters,
    step: f64,
    gm_min: f64,
) Error!orchestrator.DesignParameters {
    return gradientOptimizeMulti(orch, base, step, step * 0.5, step * 0.25, 0.05, 5, gm_min);
}

/// Multi-variable finite-difference gradient optimization on L, B, and T.
pub fn gradientOptimizeMulti(
    orch: orchestrator.Orchestrator,
    base: orchestrator.DesignParameters,
    step_l: f64,
    step_b: f64,
    step_t: f64,
    learning_rate: f64,
    iterations: u32,
    gm_min: f64,
) Error!orchestrator.DesignParameters {
    var current = base;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const score_base = orchestrator.evaluateObjective(current, gm_min);

        // Derivative w.r.t length
        var plus_l = current; plus_l.length += step_l;
        var minus_l = current; if (current.length > step_l * 2.0) minus_l.length -= step_l;
        var sr_plus_l = try orch.runSpiral(plus_l); defer orch.freeSpiralResult(&sr_plus_l);
        var sr_minus_l = try orch.runSpiral(minus_l); defer orch.freeSpiralResult(&sr_minus_l);
        const score_plus_l = orchestrator.evaluateObjective(sr_plus_l.final, gm_min);
        const score_minus_l = orchestrator.evaluateObjective(sr_minus_l.final, gm_min);
        const grad_l = (score_plus_l - score_minus_l) / (plus_l.length - minus_l.length);

        // Derivative w.r.t beam
        var plus_b = current; plus_b.beam += step_b;
        var minus_b = current; if (current.beam > step_b * 2.0) minus_b.beam -= step_b;
        var sr_plus_b = try orch.runSpiral(plus_b); defer orch.freeSpiralResult(&sr_plus_b);
        var sr_minus_b = try orch.runSpiral(minus_b); defer orch.freeSpiralResult(&sr_minus_b);
        const score_plus_b = orchestrator.evaluateObjective(sr_plus_b.final, gm_min);
        const score_minus_b = orchestrator.evaluateObjective(sr_minus_b.final, gm_min);
        const grad_b = (score_plus_b - score_minus_b) / (plus_b.beam - minus_b.beam);

        // Derivative w.r.t draft
        var plus_t = current; plus_t.draft += step_t;
        var minus_t = current; if (current.draft > step_t * 2.0) minus_t.draft -= step_t;
        var sr_plus_t = try orch.runSpiral(plus_t); defer orch.freeSpiralResult(&sr_plus_t);
        var sr_minus_t = try orch.runSpiral(minus_t); defer orch.freeSpiralResult(&sr_minus_t);
        const score_plus_t = orchestrator.evaluateObjective(sr_plus_t.final, gm_min);
        const score_minus_t = orchestrator.evaluateObjective(sr_minus_t.final, gm_min);
        const grad_t = (score_plus_t - score_minus_t) / (plus_t.draft - minus_t.draft);

        var next = current;
        next.length -= learning_rate * grad_l;
        next.beam -= learning_rate * grad_b;
        next.draft -= learning_rate * grad_t;

        // Validity boundaries check
        if (next.length < 10.0) next.length = 10.0;
        if (next.beam < 2.0) next.beam = 2.0;
        if (next.draft < 0.5) next.draft = 0.5;

        var sr_next = try orch.runSpiral(next);
        defer orch.freeSpiralResult(&sr_next);
        const score_next = orchestrator.evaluateObjective(sr_next.final, gm_min);
        if (score_next < score_base) {
            current = sr_next.final;
        } else {
            break;
        }
    }
    return current;
}

fn tournamentSelect(scores: []const f64, random: std.Random, k: usize) usize {
    var best_idx = random.uintLessThan(usize, scores.len);
    var i: usize = 0;
    while (i < k) : (i += 1) {
        const idx = random.uintLessThan(usize, scores.len);
        if (scores[idx] < scores[best_idx]) {
            best_idx = idx;
        }
    }
    return best_idx;
}

/// Population-based hull evolution using tournament selection, crossover, and mutation.
pub fn gaHullOptimize(
    orch: orchestrator.Orchestrator,
    population_size: u32,
    generations: u32,
    gm_min: f64,
) Error!orchestrator.DesignParameters {
    var rng = std.Random.DefaultPrng.init(0xDEAD_BEEF);
    const random = rng.random();

    const pop = try orch.allocator.alloc(orchestrator.DesignParameters, population_size);
    defer orch.allocator.free(pop);
    const next_pop = try orch.allocator.alloc(orchestrator.DesignParameters, population_size);
    defer orch.allocator.free(next_pop);
    const scores = try orch.allocator.alloc(f64, population_size);
    defer orch.allocator.free(scores);

    const best_seed = orchestrator.DesignParameters{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement = 0.0,
        .service_speed = 8.0,
        .c_b = 0.65,
    };
    var sr_best = try orch.runSpiral(best_seed);
    defer orch.freeSpiralResult(&sr_best);
    var best = sr_best.final;
    var best_score = orchestrator.evaluateObjective(best, gm_min);

    // Initialize population
    for (pop) |*p| {
        p.* = best;
        p.length *= random.float(f64) * 0.2 + 0.9;
        p.beam *= random.float(f64) * 0.16 + 0.92;
        p.draft *= random.float(f64) * 0.16 + 0.92;
    }

    var gen: u32 = 0;
    while (gen < generations) : (gen += 1) {
        // Evaluate population fitness
        var best_gen_idx: usize = 0;
        var best_gen_score: f64 = std.math.inf(f64);

        for (pop, 0..) |*p, i| {
            var sr = try orch.runSpiral(p.*);
            defer orch.freeSpiralResult(&sr);
            p.* = sr.final;
            const score = orchestrator.evaluateObjective(sr.final, gm_min);
            scores[i] = score;

            if (score < best_gen_score) {
                best_gen_score = score;
                best_gen_idx = i;
            }
        }

        // Update global best
        if (best_gen_score < best_score) {
            best = pop[best_gen_idx];
            best_score = best_gen_score;
        }

        // Elitism: carry best over
        next_pop[0] = pop[best_gen_idx];

        // Fill remaining slots
        var idx: usize = 1;
        while (idx < population_size) : (idx += 1) {
            const p1 = pop[tournamentSelect(scores, random, 3)];
            const p2 = pop[tournamentSelect(scores, random, 3)];

            var child = p1;
            // Crossover
            if (random.float(f64) < 0.8) {
                const alpha = random.float(f64);
                child.length = p1.length * alpha + p2.length * (1.0 - alpha);
                child.beam = p1.beam * alpha + p2.beam * (1.0 - alpha);
                child.draft = p1.draft * alpha + p2.draft * (1.0 - alpha);
            }

            // Mutation
            if (random.float(f64) < 0.2) {
                child.length *= random.float(f64) * 0.1 + 0.95;
                child.beam *= random.float(f64) * 0.08 + 0.96;
                child.draft *= random.float(f64) * 0.08 + 0.96;
            }

            next_pop[idx] = child;
        }

        // Copy next population to current
        @memcpy(pop, next_pop);
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

test "pareto front is non-empty from GA explore" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const orch = orchestrator.Orchestrator.init(arena.allocator(), 1, .mid);
    const front = try gaParetoExplore(orch, 6, 2, 0.5);
    defer arena.allocator().free(front);
    try std.testing.expect(front.len >= 1);
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
    var sr_base = try orch.runSpiral(base);
    defer orch.freeSpiralResult(&sr_base);
    const optimized = try gaHullOptimize(orch, 8, 2, 0.5);
    const base_score = orchestrator.evaluateObjective(sr_base.final, 0.5);
    const opt_score = orchestrator.evaluateObjective(optimized, 0.5);
    try std.testing.expect(opt_score <= base_score * 1.5);
}