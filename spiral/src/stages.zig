// Evans 1959 Ship Design Spiral stages.
//
// Reference: Evans, J. W. (1959), "Basic Design Concepts", J. Ship Research.
// The spiral is iterative: each loop refines interdependent disciplines until
// key metrics converge (displacement, GM, powering, structural margins, cost).

const std = @import("std");

/// Fidelity level selects approximation depth per loop.
pub const Fidelity = enum {
    /// Parametric regressions, empirical resistance, box hydrostatics.
    low,
    /// Steady Holtrop + frequency-domain seakeeping stubs.
    mid,
    /// Time-domain 6-DOF, ITTC-78 extrapolation, coupled checks.
    high,
    /// FMI co-simulation hooks (declared; external coupling).
    ultra,

    pub fn label(self: Fidelity) []const u8 {
        return switch (self) {
            .low => "low",
            .mid => "mid",
            .high => "high",
            .ultra => "ultra",
        };
    }
};

/// Ten explicit spiral stages (Evans diagram + powering feedback).
pub const Stage = enum(u8) {
    mission_requirements = 0,
    dimensions_displacement = 1,
    hull_form = 2,
    resistance_powering = 3,
    stability = 4,
    structure = 5,
    arrangements = 6,
    weights_centers = 7,
    cost_operability = 8,
    feedback_requirements = 9,

    pub fn name(self: Stage) []const u8 {
        return switch (self) {
            .mission_requirements => "mission_requirements",
            .dimensions_displacement => "dimensions_displacement",
            .hull_form => "hull_form",
            .resistance_powering => "resistance_powering",
            .stability => "stability",
            .structure => "structure",
            .arrangements => "arrangements",
            .weights_centers => "weights_centers",
            .cost_operability => "cost_operability",
            .feedback_requirements => "feedback_requirements",
        };
    }

    pub fn next(self: Stage) ?Stage {
        const raw = @intFromEnum(self);
        if (raw >= 9) return null;
        return @enumFromInt(raw + 1);
    }

    pub const all: [10]Stage = .{
        .mission_requirements,
        .dimensions_displacement,
        .hull_form,
        .resistance_powering,
        .stability,
        .structure,
        .arrangements,
        .weights_centers,
        .cost_operability,
        .feedback_requirements,
    };
};

/// Convergence criteria for spiral termination.
pub const ConvergenceCriteria = struct {
    max_loops: u32 = 5,
    gm_tol_m: f64 = 0.05,
    power_tol_kw: f64 = 50.0,
    displacement_tol_t: f64 = 100.0,
};

/// Per-loop delta tracking.
pub const LoopDelta = struct {
    loop_index: u32,
    gm_delta_m: f64,
    power_delta_kw: f64,
    displacement_delta_t: f64,
    converged: bool,
};

test "stage ordering covers full Evans loop" {
    try std.testing.expectEqual(@as(u8, 10), Stage.all.len);
    try std.testing.expectEqual(Stage.mission_requirements, Stage.all[0]);
    try std.testing.expectEqual(Stage.feedback_requirements, Stage.all[9]);
    var s: Stage = .mission_requirements;
    var count: u32 = 0;
    while (s.next()) |n| : (s = n) {
        count += 1;
    }
    try std.testing.expectEqual(@as(u32, 9), count);
}