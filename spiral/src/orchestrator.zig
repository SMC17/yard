// Evans Ship Design Spiral orchestrator — wires yard primitives per stage.

const std = @import("std");
const hydro = @import("yard_hydro");
const resistance = @import("yard_resistance");
const naval = @import("yard_naval_arch");
const similarity = @import("yard_similarity");
const fossen = @import("yard_fossen");
const stages = @import("stages.zig");

pub const Error = error{
    OutOfMemory,
    StageFailed,
    OutsideValidityEnvelope,
    ConvergenceFailed,
    SimilarityFailed,
    SimulationFailed,
};

/// Design parameters carried through spiral loops.
pub const DesignParameters = struct {
    length: f64,
    beam: f64,
    draft: f64,
    displacement: f64,
    kg: f64 = 0.0,
    /// Target service speed [m/s].
    service_speed: f64 = 8.0,
    /// Block coefficient estimate.
    c_b: f64 = 0.65,
    /// Last computed GM [m].
    gm_m: f64 = 0.0,
    /// Last estimated effective power [kW].
    estimated_power_kw: f64 = 0.0,
    /// Model scale length [m] for tank equivalence (0 = skip model path).
    model_length: f64 = 0.0,
    /// Measured model C_T from tank (0 = use Holtrop at model scale).
    model_c_t: f64 = 0.0,
};

pub const StageResult = struct {
    stage: stages.Stage,
    fidelity: stages.Fidelity,
    gm_m: f64,
    power_kw: f64,
    displacement_t: f64,
    r_total_n: f64 = 0.0,
    flags: naval.ValidityFlags = .{},
    proof_level: naval.ProofLevel = .unit_tested,
    message: []const u8 = "",
};

pub const SpiralResult = struct {
    final: DesignParameters,
    loops: u32,
    deltas: []const stages.LoopDelta,
    stage_trace: []const StageResult,
    converged: bool,
};

pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    fidelity: stages.Fidelity,
    criteria: stages.ConvergenceCriteria,
    constants: naval.PhysicalConstants = .default,

    pub fn init(allocator: std.mem.Allocator, max_loops: u32, fidelity: stages.Fidelity) Orchestrator {
        return .{
            .allocator = allocator,
            .fidelity = fidelity,
            .criteria = .{ .max_loops = max_loops },
        };
    }

    /// Run one Evans stage at the configured fidelity.
    pub fn runStage(self: Orchestrator, stage: stages.Stage, params: *DesignParameters) Error!StageResult {
        return switch (stage) {
            .mission_requirements => self.stageMission(params),
            .dimensions_displacement => self.stageDimensions(params),
            .hull_form => self.stageHullForm(params),
            .resistance_powering => self.stageResistance(params),
            .stability => self.stageStability(params),
            .structure => self.stageStub(stage, params, "structure margins deferred"),
            .arrangements => self.stageStub(stage, params, "arrangements deferred"),
            .weights_centers => self.stageWeights(params),
            .cost_operability => self.stageCost(params),
            .feedback_requirements => self.stageFeedback(params),
        };
    }

    fn stageMission(_: Orchestrator, params: *DesignParameters) Error!StageResult {
        // Seed displacement from L*B*T*C_B if not set.
        if (params.displacement <= 0.0) {
            params.displacement = params.length * params.beam * params.draft * params.c_b *
                naval.PhysicalConstants.default.rho_seawater;
        }
        return .{
            .stage = .mission_requirements,
            .fidelity = .low,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .message = "mission requirements seeded",
        };
    }

    fn stageDimensions(_: Orchestrator, params: *DesignParameters) Error!StageResult {
        const vol = params.length * params.beam * params.draft * params.c_b;
        params.displacement = vol * naval.PhysicalConstants.default.rho_seawater;
        return .{
            .stage = .dimensions_displacement,
            .fidelity = .low,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .message = "displacement from principal dimensions",
        };
    }

    fn stageHullForm(self: Orchestrator, params: *DesignParameters) Error!StageResult {
        const wigley = hydro.wigley.Hull{
            .L = params.length,
            .B = params.beam,
            .T = params.draft,
        };
        const cb = wigley.cB();
        params.c_b = cb;
        const vol = wigley.volume();
        params.displacement = vol * self.constants.rho_seawater;
        return .{
            .stage = .hull_form,
            .fidelity = if (self.fidelity == .low) .low else .mid,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .message = "Wigley closed-form hydrostatics",
            .proof_level = .unit_tested,
        };
    }

    fn stageResistance(self: Orchestrator, params: *DesignParameters) Error!StageResult {
        const rho = self.constants.rho_seawater;
        const nu = self.constants.nu;

        if (self.fidelity == .high and params.model_length > 0.0) {
            return self.stageResistanceModelTest(params, rho, nu);
        }

        const hp = resistance.holtrop.HullParticulars{
            .L = params.length,
            .B = params.beam,
            .T = params.draft,
            .displacement_vol = params.displacement / rho,
            .S = 2.6 * @sqrt(params.displacement / rho) * params.length,
            .C_B = params.c_b,
            .C_M = 0.98,
            .C_P = 0.66,
            .C_WP = 0.78,
            .lcb_pct = 0.0,
            .c_stern = 0.0,
        };
        const breakdown = resistance.holtrop.totalResistance(hp, params.service_speed, .{}) catch
            return Error.StageFailed;
        params.estimated_power_kw = breakdown.r_total * params.service_speed / 1000.0;

        return .{
            .stage = .resistance_powering,
            .fidelity = self.fidelity,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .r_total_n = breakdown.r_total,
            .message = "Holtrop-Mennen 1984 total resistance",
        };
    }

    fn stageResistanceModelTest(self: Orchestrator, params: *DesignParameters, rho: f64, nu: f64) Error!StageResult {
        const lambda = params.model_length / params.length;
        const sr = similarity.scale.ScaleRatio.fromLengths(params.model_length, params.length) catch
            return Error.SimilarityFailed;
        const v_model = sr.modelSpeedFromShip(params.service_speed, self.constants.g) catch
            return Error.SimilarityFailed;
        const s_model = 2.6 * @sqrt(params.displacement / rho) * params.length * lambda * lambda;
        const s_ship = 2.6 * @sqrt(params.displacement / rho) * params.length;

        const one_plus_k = blk: {
            const hp = resistance.holtrop.HullParticulars{
                .L = params.length,
                .B = params.beam,
                .T = params.draft,
                .displacement_vol = params.displacement / rho,
                .S = s_ship,
                .C_B = params.c_b,
                .C_M = 0.98,
                .C_P = 0.66,
                .C_WP = 0.78,
                .lcb_pct = 0.0,
                .c_stern = 0.0,
            };
            const bd = resistance.holtrop.totalResistance(hp, params.service_speed, .{}) catch
                return Error.StageFailed;
            break :blk bd.one_plus_k;
        };

        const c_t_model = if (params.model_c_t > 0.0) params.model_c_t else blk: {
            const hp_m = resistance.holtrop.HullParticulars{
                .L = params.model_length,
                .B = params.beam * lambda,
                .T = params.draft * lambda,
                .displacement_vol = params.displacement / rho * lambda * lambda * lambda,
                .S = s_model,
                .C_B = params.c_b,
                .C_M = 0.98,
                .C_P = 0.66,
                .C_WP = 0.78,
                .lcb_pct = 0.0,
                .c_stern = 0.0,
            };
            const bd_m = resistance.holtrop.totalResistance(hp_m, v_model, .{}) catch
                return Error.StageFailed;
            const r_t = bd_m.r_total;
            break :blk r_t / (0.5 * rho * v_model * v_model * s_model);
        };

        const extrap = similarity.extrapolation.extrapolateResistance(.{
            .L = params.model_length,
            .S = s_model,
            .V = v_model,
            .nu = 1.139e-6,
            .rho = 1000.0,
            .C_T = c_t_model,
            .one_plus_k = one_plus_k,
        }, .{
            .L = params.length,
            .S = s_ship,
            .V = params.service_speed,
            .nu = nu,
            .rho = rho,
            .A_T = 0.1 * params.beam * params.draft,
        }) catch return Error.StageFailed;

        params.estimated_power_kw = extrap.P_E_ship / 1000.0;

        return .{
            .stage = .resistance_powering,
            .fidelity = .high,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .r_total_n = extrap.R_T_ship,
            .message = "ITTC-78 similarity extrapolation from model test",
            .proof_level = .unit_tested,
        };
    }

    fn stageStability(self: Orchestrator, params: *DesignParameters) Error!StageResult {
        const barge = hydro.box_barge.Barge{
            .L = params.length,
            .B = params.beam,
            .T = params.draft,
        };
        const km = barge.kmT();
        const kg = if (params.kg > 0.0) params.kg else barge.kb() + 0.5 * params.draft;
        params.kg = kg;
        params.gm_m = km - kg;

        var flags: naval.ValidityFlags = .{};
        if ((params.beam / (2.0 * params.draft)) > 1.0) flags.insert(.wall_sided_assumption_valid);

        return .{
            .stage = .stability,
            .fidelity = self.fidelity,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .flags = flags,
            .message = "box-barge proxy intact stability",
        };
    }

    fn stageStub(self: Orchestrator, stage: stages.Stage, params: *DesignParameters, msg: []const u8) Error!StageResult {
        return .{
            .stage = stage,
            .fidelity = self.fidelity,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .message = msg,
        };
    }

    fn stageWeights(_: Orchestrator, params: *DesignParameters) Error!StageResult {
        // Lightship fraction proxy: adjust KG toward KB + 0.6T.
        if (params.kg <= 0.0) params.kg = params.draft * 0.6;
        return .{
            .stage = .weights_centers,
            .fidelity = .low,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .message = "weight/center proxy applied",
        };
    }

    fn stageCost(_: Orchestrator, params: *DesignParameters) Error!StageResult {
        return .{
            .stage = .cost_operability,
            .fidelity = .low,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .message = "cost proxy from displacement and power",
        };
    }

    fn stageFeedback(self: Orchestrator, params: *DesignParameters) Error!StageResult {
        if (self.fidelity == .high) {
            _ = try self.runHighFidelitySim(params);
        }
        return .{
            .stage = .feedback_requirements,
            .fidelity = self.fidelity,
            .gm_m = params.gm_m,
            .power_kw = params.estimated_power_kw,
            .displacement_t = params.displacement / 1000.0,
            .message = "feedback to mission requirements",
        };
    }

    fn runHighFidelitySim(_: Orchestrator, params: *DesignParameters) Error!void {
        const fd = fossen.fossen;
        const p = fd.Parameters{
            .M_diag = .{ 1.0e6, 1.0e6, 1.0e6, 1.0e7, 1.0e7, 1.0e7 },
            .D_lin = .{ 1.0e4, 1.0e4, 1.0e4, 1.0e5, 1.0e5, 1.0e5 },
            .K_z = 1.0e6,
            .K_phi = 1.0e7,
            .K_theta = 1.0e7,
        };
        var state: fd.State = .{ .eta = .{ 0, 0, 0, 0, 0, 0 }, .nu = .{ params.service_speed, 0, 0, 0, 0, 0 } };
        const tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            state = fd.rk4Step(state, p, tau, 0.1) catch return Error.SimulationFailed;
        }
    }

    /// Run full spiral: N loops × 10 stages until convergence or max_loops.
    pub fn runSpiral(self: Orchestrator, initial: DesignParameters) Error!SpiralResult {
        var params = initial;
        var prev_gm: f64 = 0.0;
        var prev_power: f64 = 0.0;
        var prev_disp: f64 = params.displacement;

        var deltas: std.ArrayList(stages.LoopDelta) = .empty;
        defer deltas.deinit(self.allocator);
        var trace: std.ArrayList(StageResult) = .empty;
        defer trace.deinit(self.allocator);

        var loop: u32 = 0;
        var converged = false;
        while (loop < self.criteria.max_loops) : (loop += 1) {
            for (stages.Stage.all) |stage| {
                const sr = try self.runStage(stage, &params);
                try trace.append(self.allocator, sr);
            }
            const gm_delta = @abs(params.gm_m - prev_gm);
            const power_delta = @abs(params.estimated_power_kw - prev_power);
            const disp_delta = @abs(params.displacement - prev_disp) / 1000.0;
            const loop_converged = gm_delta < self.criteria.gm_tol_m and
                power_delta < self.criteria.power_tol_kw and
                disp_delta < self.criteria.displacement_tol_t;
            try deltas.append(self.allocator, .{
                .loop_index = loop,
                .gm_delta_m = gm_delta,
                .power_delta_kw = power_delta,
                .displacement_delta_t = disp_delta,
                .converged = loop_converged,
            });
            if (loop_converged and loop > 0) {
                converged = true;
                break;
            }
            prev_gm = params.gm_m;
            prev_power = params.estimated_power_kw;
            prev_disp = params.displacement;
        }

        const deltas_slice = try deltas.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(deltas_slice);
        const trace_slice = try trace.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(trace_slice);

        return .{
            .final = params,
            .loops = loop,
            .deltas = deltas_slice,
            .stage_trace = trace_slice,
            .converged = converged,
        };
    }

    pub fn freeSpiralResult(self: Orchestrator, result: *SpiralResult) void {
        self.allocator.free(result.deltas);
        self.allocator.free(result.stage_trace);
    }
};

/// Multi-objective score for optimization (lower is better).
pub fn evaluateObjective(params: DesignParameters, gm_min: f64) f64 {
    const power_term = params.estimated_power_kw / 1000.0;
    const gm_penalty = if (params.gm_m < gm_min) (gm_min - params.gm_m) * 100.0 else 0.0;
    const disp_term = params.displacement / 1.0e6;
    return power_term + gm_penalty + disp_term;
}

test "single spiral loop on cargo-scale hull" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var orch = Orchestrator.init(arena.allocator(), 2, .mid);
    var result = try orch.runSpiral(.{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement = 0.0,
        .kg = 5.0,
        .service_speed = 8.0,
        .c_b = 0.65,
    });
    defer orch.freeSpiralResult(&result);

    try std.testing.expect(result.final.gm_m > 0.0);
    try std.testing.expect(result.final.estimated_power_kw > 0.0);
    try std.testing.expect(result.stage_trace.len >= 10);
}

test "high-fidelity model test extrapolation path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var orch = Orchestrator.init(arena.allocator(), 1, .high);
    var params = DesignParameters{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement = 8500.0 * 1025.0,
        .service_speed = 8.0,
        .c_b = 0.65,
        .model_length = 5.0,
    };
    const sr = try orch.runStage(.resistance_powering, &params);
    try std.testing.expect(sr.power_kw > 0.0);
    try std.testing.expect(sr.r_total_n > 0.0);
    try std.testing.expectEqualStrings("ITTC-78 similarity extrapolation from model test", sr.message);
}