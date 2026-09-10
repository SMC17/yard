//! L0 constraint mirror for Yard-Sea-v0 (box-like particulars).
const std = @import("std");

pub const Hull = struct {
    L: f64 = 120,
    B: f64 = 20,
    T: f64 = 8,
    Cb: f64 = 0.75,
    lcb_frac: f64 = 0,
    kg_frac: f64 = 0.55,
};

pub fn volume(h: Hull) f64 {
    return h.L * h.B * h.T * h.Cb;
}

pub fn gm0(h: Hull) f64 {
    const v = volume(h);
    const kb = 0.5 * h.T;
    const bm = (h.L * h.B * h.B * h.B / 12.0) / v;
    const depth = @max(h.T * 1.25, h.T + 0.5);
    const kg = h.kg_frac * depth;
    return kb + bm - kg;
}

pub fn l0_feasible(h: Hull) bool {
    if (h.L <= 0 or h.B <= 0 or h.T <= 0) return false;
    const lb = h.L / h.B;
    const tb = h.T / h.B;
    if (lb < 3.0 or lb > 12.0) return false;
    if (tb < 0.15 or tb > 0.55) return false;
    if (h.Cb < 0.45 or h.Cb > 0.95) return false;
    if (h.lcb_frac < -0.05 or h.lcb_frac > 0.05) return false;
    if (gm0(h) < 0.15) return false;
    if (h.B / (2.0 * h.T) <= 0.8) return false;
    return true;
}

test "default hull feasible" {
    try std.testing.expect(l0_feasible(.{}));
}

test "bad cb rejected" {
    try std.testing.expect(!l0_feasible(.{ .Cb = 0.2 }));
}
