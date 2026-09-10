// Rectangular box barge.
//
// All hydrostatic quantities closed-form. Provides a sanity-check baseline:
// every numerical integrator must reproduce these exactly because the geometry
// is rectangular and the integrands are polynomial in (x, z) of degree <= 1.

const std = @import("std");

pub const Barge = struct {
    L: f64,
    B: f64,
    T: f64,

    pub fn halfBreadth(self: Barge, x: f64, z_below_wl: f64) f64 {
        _ = z_below_wl;
        if (@abs(x) > 0.5 * self.L) return 0.0;
        return 0.5 * self.B;
    }

    pub fn volume(self: Barge) f64 {
        return self.L * self.B * self.T;
    }

    pub fn waterplaneArea(self: Barge) f64 {
        return self.L * self.B;
    }

    /// VCB from keel = T / 2 (rectangular cross-section, uniform along L).
    pub fn kb(self: Barge) f64 {
        return 0.5 * self.T;
    }

    pub fn lcb(_: Barge) f64 {
        return 0.0;
    }

    pub fn iT(self: Barge) f64 {
        return self.L * self.B * self.B * self.B / 12.0;
    }

    pub fn iL(self: Barge) f64 {
        return self.B * self.L * self.L * self.L / 12.0;
    }

    pub fn bmT(self: Barge) f64 {
        return self.iT() / self.volume();
    }

    pub fn bmL(self: Barge) f64 {
        return self.iL() / self.volume();
    }

    pub fn kmT(self: Barge) f64 {
        return self.kb() + self.bmT();
    }

    pub fn kmL(self: Barge) f64 {
        return self.kb() + self.bmL();
    }

    pub fn cB(_: Barge) f64 {
        return 1.0;
    }

    pub fn cM(_: Barge) f64 {
        return 1.0;
    }

    pub fn cP(_: Barge) f64 {
        return 1.0;
    }

    pub fn cW(_: Barge) f64 {
        return 1.0;
    }

    /// Sectional area A(x) = B * T (uniform). Endpoints zero (no plating outside hull).
    pub fn sectionalAreas(self: Barge, stations: []f64) void {
        const n = stations.len;
        std.debug.assert(n >= 2);
        const A: f64 = self.B * self.T;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            // Interior stations have sectional area A; the box ends abruptly.
            // For Simpson integration the convention is that the cargo block
            // spans [-L/2, L/2] with vertical end-walls; sectional area is
            // A everywhere in the interval, and the endpoints (i = 0 and i = n-1)
            // are at the walls, where A is also A (the wall has area, not zero).
            // This differs from a streamlined hull where endpoints are zero.
            stations[i] = A;
        }
    }

    /// Waterplane half-breadth at design draft: B/2 everywhere.
    pub fn waterlineOrdinates(self: Barge, stations: []f64) void {
        const n = stations.len;
        std.debug.assert(n >= 2);
        const half_B: f64 = 0.5 * self.B;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            stations[i] = half_B;
        }
    }
};

const expectApproxEqRel = std.testing.expectApproxEqRel;

test "box-barge volume equals L B T" {
    const b = Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    try expectApproxEqRel(@as(f64, 60.0), b.volume(), 1e-15);
}

test "box-barge KB equals T/2" {
    const b = Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    try expectApproxEqRel(@as(f64, 0.75), b.kb(), 1e-15);
}

test "box-barge BM_T equals B^2 / (12 T)" {
    const b = Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    const expected: f64 = 16.0 / (12.0 * 1.5);
    try expectApproxEqRel(expected, b.bmT(), 1e-15);
}

test "box-barge BM_L equals L^2 / (12 T)" {
    const b = Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    const expected: f64 = 100.0 / (12.0 * 1.5);
    try expectApproxEqRel(expected, b.bmL(), 1e-15);
}

test "box-barge KM_T equation matches Biran 2013 worked example" {
    // Biran 2013 Ch.10 box-barge example: L=10, B=4, T=1.5
    // KB = 0.75, BM_T = 8/9 ~ 0.8889, KM_T = 1.6389
    const b = Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    try expectApproxEqRel(@as(f64, 1.6389), b.kmT(), 1e-4);
}

test "box-barge coefficients all unity" {
    const b = Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    try expectApproxEqRel(@as(f64, 1.0), b.cB(), 1e-15);
    try expectApproxEqRel(@as(f64, 1.0), b.cM(), 1e-15);
    try expectApproxEqRel(@as(f64, 1.0), b.cP(), 1e-15);
    try expectApproxEqRel(@as(f64, 1.0), b.cW(), 1e-15);
}
