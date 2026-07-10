//! Spectral bridge: response spectrum -> the variances the criteria and
//! event statistics consume. Closes the rao-spectrum -> operability chain.
//!
//!   m_n = integral f^n... (here in angular frequency omega):
//!   m0 = variance of displacement, m2 = variance of velocity,
//!   m4 = variance of acceleration, Tz = 2 pi sqrt(m0/m2),
//!   bandwidth eps = sqrt(1 - m2^2/(m0 m4)).

const std = @import("std");

pub const SpectrumSample = struct {
    omega_rad_s: f64,
    /// Response spectral density [unit^2 s/rad].
    s: f64,
};

pub const Moments = struct {
    m0: f64,
    m2: f64,
    m4: f64,

    pub fn rms(self: Moments) f64 {
        return @sqrt(self.m0);
    }
    pub fn rmsVelocity(self: Moments) f64 {
        return @sqrt(self.m2);
    }
    pub fn rmsAcceleration(self: Moments) f64 {
        return @sqrt(self.m4);
    }
    /// Mean zero-upcrossing period [s].
    pub fn tz(self: Moments) f64 {
        if (self.m2 <= 0) return 0;
        return 2.0 * std.math.pi * @sqrt(self.m0 / self.m2);
    }
    /// Spectral bandwidth (0 = narrow band; Rayleigh statistics valid).
    pub fn bandwidth(self: Moments) f64 {
        if (self.m0 <= 0 or self.m4 <= 0) return 1.0;
        return @sqrt(@max(0.0, 1.0 - self.m2 * self.m2 / (self.m0 * self.m4)));
    }
};

/// Trapezoid spectral moments m0, m2, m4 over the sampled spectrum.
pub fn moments(samples: []const SpectrumSample) Moments {
    var m: Moments = .{ .m0 = 0, .m2 = 0, .m4 = 0 };
    if (samples.len < 2) return m;
    for (1..samples.len) |i| {
        const a = samples[i - 1];
        const b = samples[i];
        const dw = b.omega_rad_s - a.omega_rad_s;
        const w2a = a.omega_rad_s * a.omega_rad_s;
        const w2b = b.omega_rad_s * b.omega_rad_s;
        m.m0 += 0.5 * (a.s + b.s) * dw;
        m.m2 += 0.5 * (a.s * w2a + b.s * w2b) * dw;
        m.m4 += 0.5 * (a.s * w2a * w2a + b.s * w2b * w2b) * dw;
    }
    return m;
}

test "rectangular spectrum: closed-form moments" {
    // S = 2 over omega in [1, 2]:
    //   m0 = 2, m2 = 2*(8-1)/3 = 14/3, m4 = 2*(32-1)/5 = 62/5.
    var samples: [101]SpectrumSample = undefined;
    for (&samples, 0..) |*p, i| {
        const w = 1.0 + @as(f64, @floatFromInt(i)) / 100.0;
        p.* = .{ .omega_rad_s = w, .s = 2.0 };
    }
    const m = moments(&samples);
    try std.testing.expectApproxEqRel(@as(f64, 2.0), m.m0, 1e-6);
    try std.testing.expectApproxEqRel(@as(f64, 14.0 / 3.0), m.m2, 1e-3);
    try std.testing.expectApproxEqRel(@as(f64, 62.0 / 5.0), m.m4, 1e-3);
    // Tz = 2 pi sqrt(2 / (14/3)) = 2 pi sqrt(3/7).
    try std.testing.expectApproxEqRel(2.0 * std.math.pi * @sqrt(3.0 / 7.0), m.tz(), 1e-3);
    // Bandwidth of this wide rectangle: eps = sqrt(1 - (14/3)^2/(2*62/5)).
    const eps = @sqrt(1.0 - (14.0 / 3.0) * (14.0 / 3.0) / (2.0 * 62.0 / 5.0));
    try std.testing.expectApproxEqRel(eps, m.bandwidth(), 1e-2);
}

test "narrow spike has near-zero bandwidth" {
    // Rectangle centred on omega = 1, width 0.05.
    var samples: [41]SpectrumSample = undefined;
    for (&samples, 0..) |*p, i| {
        const w = 0.975 + @as(f64, @floatFromInt(i)) * 0.00125;
        p.* = .{ .omega_rad_s = w, .s = 1.0 };
    }
    const m = moments(&samples);
    try std.testing.expect(m.bandwidth() < 0.05);
    try std.testing.expectApproxEqRel(2.0 * std.math.pi, m.tz(), 1e-2);
}
