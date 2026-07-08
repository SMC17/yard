//! Box-barge damage stability: lost-buoyancy draft rise → residual GM + IS Code.

const std = @import("std");
const hydro = @import("yard_hydro");
const stability = @import("yard_stability");
const naval = @import("yard_naval_arch");

pub const Error = error{
    FloodingExceedsHullDepth,
    InvalidDamageCase,
    IsCodeEvaluationFailed,
    OutOfMemory,
};

pub const DamageCase = struct {
    /// Flooded compartment length [m]
    l_lost_m: f64,
    /// Permeability [0, 1]
    mu: f64 = 1.0,
    /// Hull depth (moulded) [m]
    depth_m: f64,
    /// Number of equal longitudinal compartments (for documentation)
    n_compartments: u32 = 5,
};

pub const Input = struct {
    particulars: naval.PrincipalParticulars,
    loading: naval.LoadingCondition,
    damage: DamageCase,
    constants: naval.PhysicalConstants = .default,
    max_heel_deg: f64 = 40.0,
    heel_step_deg: f64 = 5.0,
};

pub const Output = struct {
    intact: struct {
        hydrostatics: naval.Hydrostatics,
        stability: naval.StabilitySummary,
    },
    damaged: struct {
        t_damaged_m: f64,
        hydrostatics: naval.Hydrostatics,
        stability: naval.StabilitySummary,
        is_code: naval.IsCodeResult,
    },
    flags: naval.ValidityFlags,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn evaluate(allocator: std.mem.Allocator, input: Input) Error!Output {
    const p = input.particulars;
    const barge = hydro.box_barge.Barge{ .L = p.L, .B = p.B, .T = p.T };

    const V_intact = barge.volume();
    const disp = V_intact * input.constants.rho_seawater;
    const kb_intact = barge.kb();
    const bm_t_intact = barge.bmT();
    const km_t_intact = barge.kmT();
    const gm0_intact = km_t_intact - input.loading.kg_m;

    var tanks = try allocator.alloc(stability.gz.Tank, input.loading.tanks.len);
    defer allocator.free(tanks);
    for (input.loading.tanks, 0..) |t, i| {
        tanks[i] = .{
            .rho_fluid = t.rho_fluid,
            .i_fs = stability.gz.rectTankIfs(t.l_m, t.b_m),
        };
    }
    const gm_corr_intact = stability.gz.effectiveGM(gm0_intact, tanks, input.constants.rho_seawater, V_intact);

    const t_damaged = stability.damage.boxBargeOneCompartment(
        p.L,
        input.damage.l_lost_m,
        p.T,
        input.damage.depth_m,
        input.damage.mu,
    ) catch |err| switch (err) {
        error.FloodingExceedsHullDepth => return Error.FloodingExceedsHullDepth,
        error.InvalidPermeability, error.NonPositiveDimension => return Error.InvalidDamageCase,
    };

    const L_rem = p.L - input.damage.l_lost_m;
    const V_damaged = L_rem * p.B * t_damaged;
    const kb_damaged = t_damaged / 2.0;
    const i_t = stability.damage.boxBargeIntactIT(p.L, input.damage.l_lost_m, p.B);
    const bm_t_damaged = i_t / V_damaged;
    const km_t_damaged = kb_damaged + bm_t_damaged;
    const gm0_damaged = km_t_damaged - input.loading.kg_m;
    const gm_corr_damaged = stability.gz.effectiveGM(gm0_damaged, tanks, input.constants.rho_seawater, V_damaged);

    const wall_sided_valid = (p.B / (2.0 * t_damaged)) > 1.0;

    var flags: naval.ValidityFlags = .{};
    flags.insert(.data_insufficient); // damage GZ simplified — no floodwater shift modeled
    if (wall_sided_valid) flags.insert(.wall_sided_assumption_valid);
    if (input.loading.tanks.len > 0) flags.insert(.free_surface_applied);
    if (gm_corr_damaged < 0.15) flags.insert(.outside_validity_envelope);

    const n_curve = @as(usize, @intFromFloat(@floor(input.max_heel_deg / input.heel_step_deg))) + 1;
    var angles_rad = try allocator.alloc(f64, n_curve);
    defer allocator.free(angles_rad);
    var gz_vals = try allocator.alloc(f64, n_curve);
    defer allocator.free(gz_vals);

    {
        var i: usize = 0;
        var deg: f64 = 0.0;
        while (i < n_curve) : (i += 1) {
            const rad = naval.units.degToRad(deg);
            angles_rad[i] = rad;
            gz_vals[i] = if (wall_sided_valid)
                stability.gz.wallSidedGZ(gm_corr_damaged, bm_t_damaged, rad)
            else
                stability.gz.smallAngleGZ(gm_corr_damaged, rad);
            deg += input.heel_step_deg;
        }
    }

    const ic = stability.is_code.evaluate(angles_rad, gz_vals, gm0_damaged) catch return Error.IsCodeEvaluationFailed;

    const toVerdict = struct {
        fn map(v: stability.is_code.Verdict) naval.types.CriterionVerdict {
            return switch (v) {
                .pass => .pass,
                .fail => .fail,
            };
        }
    }.map;

    return .{
        .intact = .{
            .hydrostatics = .{
                .volume_m3 = V_intact,
                .displacement_kg = disp,
                .kb_m = kb_intact,
                .bm_t_m = bm_t_intact,
                .km_t_m = km_t_intact,
                .lcb_m = 0.0,
                .c_b = 1.0,
            },
            .stability = .{
                .gm0_m = gm0_intact,
                .gm_corrected_m = gm_corr_intact,
                .gg_prime_m = gm0_intact - gm_corr_intact,
                .wall_sided_valid = (p.B / (2.0 * p.T)) > 1.0,
            },
        },
        .damaged = .{
            .t_damaged_m = t_damaged,
            .hydrostatics = .{
                .volume_m3 = V_damaged,
                .displacement_kg = V_damaged * input.constants.rho_seawater,
                .kb_m = kb_damaged,
                .bm_t_m = bm_t_damaged,
                .km_t_m = km_t_damaged,
                .lcb_m = 0.0,
                .c_b = V_damaged / (p.L * p.B * t_damaged),
            },
            .stability = .{
                .gm0_m = gm0_damaged,
                .gm_corrected_m = gm_corr_damaged,
                .gg_prime_m = gm0_damaged - gm_corr_damaged,
                .wall_sided_valid = wall_sided_valid,
            },
            .is_code = .{
                .area_0_30 = toVerdict(ic.area_0_30),
                .area_0_40 = toVerdict(ic.area_0_40),
                .area_30_40 = toVerdict(ic.area_30_40),
                .gz_at_30 = toVerdict(ic.gz_at_30),
                .angle_gz_max = toVerdict(ic.angle_gz_max),
                .gm_0 = toVerdict(ic.gm_0),
                .overall = toVerdict(ic.overall),
                .values = .{
                    .area_0_30 = ic.values.area_0_30,
                    .area_0_40 = ic.values.area_0_40,
                    .area_30_40 = ic.values.area_30_40,
                    .gz_at_30 = ic.values.gz_at_30,
                    .angle_gz_max_deg = ic.values.angle_gz_max_deg,
                    .gm_0 = ic.values.gm_0,
                },
            },
        },
        .flags = flags,
    };
}

test "canonical damage case matches codex T_damaged=1.875" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const out = try evaluate(arena.allocator(), .{
        .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
        .loading = .{ .kg_m = 1.0, .tanks = &.{} },
        .damage = .{ .l_lost_m = 2.0, .mu = 1.0, .depth_m = 3.0 },
    });

    try std.testing.expectApproxEqAbs(@as(f64, 1.875), out.damaged.t_damaged_m, 1e-6);
    try std.testing.expect(out.damaged.stability.gm_corrected_m > 0.0);
}