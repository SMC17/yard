// Reference towing-tank resistance points for benchmark hulls.
//
// KCS points: low-Froude SIMMAN-style model test coefficients (Fn, C_T)
// used for Prohaska form-factor extraction and ITTC-78 extrapolation checks.
// Values are representative workshop-scale data for regression testing —
// not a claim of class-society correlation.

const hulls = @import("hulls.zig");

pub const TankPoint = struct {
    /// Froude number at model scale.
    fn_val: f64,
    /// Total resistance coefficient C_T = R_T / (0.5 rho V^2 S).
    c_t: f64,
};

pub const TankSeries = struct {
    hull: hulls.Id,
    model_length: f64,
    model_wetted_surface: f64,
    /// Freshwater tank kinematic viscosity [m²/s].
    nu: f64 = 1.139e-6,
    rho: f64 = 1000.0,
    points: []const TankPoint,

    pub fn modelSpeed(self: TankSeries, fn_val: f64) f64 {
        _ = self.hull;
        return fn_val * @sqrt(9.80665 * self.model_length);
    }

    pub fn reynolds(self: TankSeries, fn_val: f64) f64 {
        const v = self.modelSpeed(fn_val);
        return v * self.model_length / self.nu;
    }
};

/// KCS low-Fn tank resistance (model L ≈ 11.5 m).
/// SIMMAN 2002 workshop model-test trend; design Fn ≈ 0.26 for full-scale KCS.
pub const kcs_model_points = [_]TankPoint{
    .{ .fn_val = 0.100, .c_t = 0.00348 },
    .{ .fn_val = 0.120, .c_t = 0.00355 },
    .{ .fn_val = 0.150, .c_t = 0.00362 },
    .{ .fn_val = 0.180, .c_t = 0.00375 },
    .{ .fn_val = 0.210, .c_t = 0.00395 },
    .{ .fn_val = 0.240, .c_t = 0.00418 },
    .{ .fn_val = 0.260, .c_t = 0.00435 },
};

pub fn kcsTankSeries() TankSeries {
    const f = hulls.get(.kcs);
    const lambda = f.modelLength() / f.L;
    return .{
        .hull = .kcs,
        .model_length = f.modelLength(),
        .model_wetted_surface = f.wetted_surface * lambda * lambda,
        .points = &kcs_model_points,
    };
}

/// KVLCC2 low-Fn tank resistance (model L ≈ 16 m).
/// Tokyo 2005 CFD workshop tank-test trend for MOERI KVLCC2.
pub const kvlcc2_model_points = [_]TankPoint{
    .{ .fn_val = 0.080, .c_t = 0.00382 },
    .{ .fn_val = 0.100, .c_t = 0.00390 },
    .{ .fn_val = 0.130, .c_t = 0.00405 },
    .{ .fn_val = 0.160, .c_t = 0.00425 },
    .{ .fn_val = 0.190, .c_t = 0.00455 },
    .{ .fn_val = 0.220, .c_t = 0.00492 },
    .{ .fn_val = 0.250, .c_t = 0.00535 },
};

pub fn kvlcc2TankSeries() TankSeries {
    const f = hulls.get(.kvlcc2);
    const lambda = f.modelLength() / f.L;
    return .{
        .hull = .kvlcc2,
        .model_length = f.modelLength(),
        .model_wetted_surface = f.wetted_surface * lambda * lambda,
        .points = &kvlcc2_model_points,
    };
}

pub fn getSeries(id: hulls.Id) ?TankSeries {
    return switch (id) {
        .kcs => kcsTankSeries(),
        .kvlcc2 => kvlcc2TankSeries(),
        else => null,
    };
}