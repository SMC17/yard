// Model-test → full-scale extrapolation using tank C_T series + ITTC-78.

const std = @import("std");
const resistance = @import("yard_resistance");
const similarity = @import("yard_similarity");
const ittc78 = @import("yard_ittc78");
const towing_tank = @import("yard_towing_tank");
const hulls = @import("hulls.zig");
const tank_data = @import("tank_data.zig");

pub const Error = error{
    NoTankData,
    FitFailed,
    ExtrapolationFailed,
};

pub const Result = struct {
    hull: hulls.Id,
    design_fn: f64,
    c_t_model: f64,
    one_plus_k: f64,
    p_e_ship: f64,
    p_e_ittc78: f64,
    relative_error: f64,
};

fn cF(rn: f64) !f64 {
    return resistance.ittc57.cF(rn);
}

/// Extrapolate at design Froude using measured tank C_T and Prohaska (1+k).
pub fn extrapolateAtDesignFn(series: tank_data.TankSeries, design_fn: f64) Error!Result {
    const f = hulls.get(series.hull);
    const v_model = series.modelSpeed(design_fn);

    // Build Prohaska arrays from tank points.
    var fn_arr: [8]f64 = undefined;
    var ct_arr: [8]f64 = undefined;
    var cf_arr: [8]f64 = undefined;
    const n = series.points.len;
    if (n < 3) return Error.NoTankData;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const pt = series.points[i];
        fn_arr[i] = pt.fn_val;
        ct_arr[i] = pt.c_t;
        const rn = series.reynolds(pt.fn_val);
        cf_arr[i] = cF(rn) catch return Error.ExtrapolationFailed;
    }

    const fit = towing_tank.prohaska.fit(fn_arr[0..n], ct_arr[0..n], cf_arr[0..n]) catch
        return Error.FitFailed;

    // C_T at design from nearest tank point or last point.
    var c_t_design = series.points[n - 1].c_t;
    for (series.points) |pt| {
        if (@abs(pt.fn_val - design_fn) < 0.02) c_t_design = pt.c_t;
    }

    const sim = similarity.extrapolation.extrapolateResistance(.{
        .L = series.model_length,
        .S = series.model_wetted_surface,
        .V = v_model,
        .nu = series.nu,
        .rho = series.rho,
        .C_T = c_t_design,
        .one_plus_k = fit.one_plus_k,
    }, .{
        .L = f.L,
        .S = f.wetted_surface,
        .V = f.service_speed,
        .nu = 1.188e-6,
        .rho = 1025.0,
        .A_T = 0.1 * f.B * f.T,
    }) catch return Error.ExtrapolationFailed;

    const ittc = ittc78.chain.extrapolate(.{
        .L = series.model_length,
        .S = series.model_wetted_surface,
        .V = v_model,
        .nu = series.nu,
        .C_T = c_t_design,
        .rho = series.rho,
    }, .{
        .L = f.L,
        .S = f.wetted_surface,
        .V = f.service_speed,
        .nu = 1.188e-6,
        .rho = 1025.0,
        .A_T = 0.1 * f.B * f.T,
    }, .{ .one_plus_k = fit.one_plus_k, .w = 0.3, .t = 0.18, .eta_R = 1.0, .eta_S = 0.98 }, .{
        .D = 7.0,
        .n_s = 1.5,
        .K_T_s = 0.18,
        .K_Q_s = 0.028,
    }) catch return Error.ExtrapolationFailed;

    const rel = @abs(sim.P_E_ship - ittc.P_E_ship) / ittc.P_E_ship;

    return .{
        .hull = series.hull,
        .design_fn = design_fn,
        .c_t_model = c_t_design,
        .one_plus_k = fit.one_plus_k,
        .p_e_ship = sim.P_E_ship,
        .p_e_ittc78 = ittc.P_E_ship,
        .relative_error = rel,
    };
}

test "KCS tank extrapolation agrees with ITTC-78 chain" {
    const series = tank_data.kcsTankSeries();
    const r = try extrapolateAtDesignFn(series, 0.26);
    try std.testing.expect(r.one_plus_k > 1.0);
    try std.testing.expect(r.p_e_ship > 0.0);
    try std.testing.expect(r.relative_error < 0.02);
}