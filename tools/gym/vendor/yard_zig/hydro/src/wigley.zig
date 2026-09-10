// Wigley parabolic hull.
//
// Canonical mathematical form (z measured downward from waterline):
//
//   y(x, z) = (B / 2) * (1 - (2 x / L)^2) * (1 - (z / T)^2)
//
// x in [-L/2, L/2]; z in [0, T]. y is half-breadth (port = starboard).
// Source: Journee 1992; Kajitani-Miyata 1983 cooperative experiment.
//
// All hydrostatic quantities below are closed-form rationals in (L, B, T).
// Use these as exact validation targets for numerical hydrostatic integrators.
//
// Coordinate convention:
//   - z' downward from waterline (matches the parametric form).
//   - z upward from keel (naval-architecture convention) = T - z'.
//   - LCB = 0 by symmetry of y in x.
//   - VCB (from keel) = T - (3 T / 8) = 5 T / 8.

const std = @import("std");
const simpson = @import("simpson.zig");

pub const Hull = struct {
    L: f64,
    B: f64,
    T: f64,

    /// Half-breadth at longitudinal x and depth-below-waterline z'.
    pub fn halfBreadth(self: Hull, x: f64, z_below_wl: f64) f64 {
        const xn = 2.0 * x / self.L;
        const zn = z_below_wl / self.T;
        return 0.5 * self.B * (1.0 - xn * xn) * (1.0 - zn * zn);
    }

    /// Closed-form volume of displacement: V = (4/9) L B T.
    pub fn volume(self: Hull) f64 {
        return (4.0 / 9.0) * self.L * self.B * self.T;
    }

    /// Closed-form waterplane area: A_W = (2/3) L B.
    pub fn waterplaneArea(self: Hull) f64 {
        return (2.0 / 3.0) * self.L * self.B;
    }

    /// Vertical center of buoyancy from keel: KB = 5 T / 8.
    pub fn kb(self: Hull) f64 {
        return 5.0 * self.T / 8.0;
    }

    /// Longitudinal center of buoyancy from amidships: zero by symmetry.
    pub fn lcb(_: Hull) f64 {
        return 0.0;
    }

    /// Transverse moment of inertia of waterplane: I_T = (4/105) L B^3.
    pub fn iT(self: Hull) f64 {
        return (4.0 / 105.0) * self.L * self.B * self.B * self.B;
    }

    /// Longitudinal moment of inertia of waterplane about LCF (= midship):
    /// I_L = (1/30) B L^3.
    pub fn iL(self: Hull) f64 {
        return (1.0 / 30.0) * self.B * self.L * self.L * self.L;
    }

    /// Transverse metacentric radius: BM_T = I_T / V = (3/35) B^2 / T.
    pub fn bmT(self: Hull) f64 {
        return (3.0 / 35.0) * self.B * self.B / self.T;
    }

    /// Longitudinal metacentric radius: BM_L = I_L / V = (3/40) L^2 / T.
    pub fn bmL(self: Hull) f64 {
        return (3.0 / 40.0) * self.L * self.L / self.T;
    }

    /// Transverse metacentric height above keel: KM_T = KB + BM_T.
    pub fn kmT(self: Hull) f64 {
        return self.kb() + self.bmT();
    }

    /// Longitudinal metacentric height above keel: KM_L = KB + BM_L.
    pub fn kmL(self: Hull) f64 {
        return self.kb() + self.bmL();
    }

    /// Block coefficient: C_B = V / (L B T) = 4 / 9.
    pub fn cB(_: Hull) f64 {
        return 4.0 / 9.0;
    }

    /// Midship section area coefficient: C_M = A_midship / (B T) = 2 / 3.
    pub fn cM(_: Hull) f64 {
        return 2.0 / 3.0;
    }

    /// Prismatic coefficient: C_P = C_B / C_M = 2 / 3.
    pub fn cP(_: Hull) f64 {
        return 2.0 / 3.0;
    }

    /// Waterplane area coefficient: C_W = A_W / (L B) = 2 / 3.
    pub fn cW(_: Hull) f64 {
        return 2.0 / 3.0;
    }

    /// Sectional half-breadth array at uniform x stations across [-L/2, L/2],
    /// at a specified depth-below-waterline z_below_wl. Caller-allocated buffer.
    /// n_stations is the number of stations (= odd integer for Simpson 1/3 use).
    pub fn waterlineOrdinates(
        self: Hull,
        z_below_wl: f64,
        stations: []f64,
    ) void {
        const n = stations.len;
        std.debug.assert(n >= 2);
        const dx = self.L / @as(f64, @floatFromInt(n - 1));
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const x = -0.5 * self.L + @as(f64, @floatFromInt(i)) * dx;
            stations[i] = self.halfBreadth(x, z_below_wl);
        }
    }

    /// Sectional area A(x) at each station, integrated analytically in z:
    /// A(x) = 2 * integral_0^T y(x, z) dz = (2/3) B T (1 - (2x/L)^2).
    /// Caller-allocated buffer; n_stations may be any >= 2.
    pub fn sectionalAreas(self: Hull, stations: []f64) void {
        const n = stations.len;
        std.debug.assert(n >= 2);
        const dx = self.L / @as(f64, @floatFromInt(n - 1));
        const A_M = (2.0 / 3.0) * self.B * self.T;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const x = -0.5 * self.L + @as(f64, @floatFromInt(i)) * dx;
            const xn = 2.0 * x / self.L;
            stations[i] = A_M * (1.0 - xn * xn);
        }
    }
};

const expectApproxEqRel = std.testing.expectApproxEqRel;

test "Wigley closed-form coefficients are rational fractions" {
    const h = Hull{ .L = 100.0, .B = 10.0, .T = 5.0 };
    try expectApproxEqRel(@as(f64, 4.0 / 9.0), h.cB(), 1e-15);
    try expectApproxEqRel(@as(f64, 2.0 / 3.0), h.cM(), 1e-15);
    try expectApproxEqRel(@as(f64, 2.0 / 3.0), h.cP(), 1e-15);
    try expectApproxEqRel(@as(f64, 2.0 / 3.0), h.cW(), 1e-15);
}

test "Wigley closed-form volume matches (4/9) L B T" {
    const h = Hull{ .L = 2.5, .B = 0.25, .T = 0.15625 };
    const expected = (4.0 / 9.0) * 2.5 * 0.25 * 0.15625;
    try expectApproxEqRel(expected, h.volume(), 1e-15);
}

test "Wigley closed-form KB equals 5 T / 8" {
    const h = Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    try expectApproxEqRel(@as(f64, 2.5), h.kb(), 1e-15);
}

test "Wigley closed-form BM_T equals 3 B^2 / (35 T)" {
    const h = Hull{ .L = 100.0, .B = 14.0, .T = 7.0 };
    const expected: f64 = 3.0 * 14.0 * 14.0 / (35.0 * 7.0);
    try expectApproxEqRel(expected, h.bmT(), 1e-15);
}

test "Wigley closed-form BM_L equals 3 L^2 / (40 T)" {
    const h = Hull{ .L = 200.0, .B = 20.0, .T = 8.0 };
    const expected: f64 = 3.0 * 200.0 * 200.0 / (40.0 * 8.0);
    try expectApproxEqRel(expected, h.bmL(), 1e-15);
}

test "Wigley waterline ordinates symmetric in x at draft" {
    const h = Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    var ords: [21]f64 = undefined;
    h.waterlineOrdinates(0.0, &ords);
    // Symmetry: ords[i] == ords[20 - i].
    var i: usize = 0;
    while (i < 11) : (i += 1) {
        try std.testing.expectApproxEqRel(ords[i], ords[20 - i], 1e-15);
    }
    // Endpoints zero.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), ords[0], 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), ords[20], 1e-15);
    // Midship at z = 0 is B / 2.
    try std.testing.expectApproxEqRel(@as(f64, 5.0), ords[10], 1e-15);
}

test "Wigley sectional area at midship equals A_M = (2/3) B T" {
    const h = Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    var areas: [21]f64 = undefined;
    h.sectionalAreas(&areas);
    const expected = (2.0 / 3.0) * 10.0 * 4.0;
    try std.testing.expectApproxEqRel(expected, areas[10], 1e-15);
    // Endpoints zero.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), areas[0], 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), areas[20], 1e-15);
}
