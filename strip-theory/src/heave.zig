// 1-DOF heave equation of motion in the frequency domain.
//
// Mass + added mass m_eff(omega) = M + A_33(omega), damping
// B_33(omega), restoring C_33 = rho g A_W. Forcing F_3(omega) is the
// Froude-Krylov plus diffraction excitation per unit wave amplitude.
//
// The complex response amplitude X (per unit wave amplitude) is
//
//   X(omega) = F_3(omega) / [ -(M + A_33) omega^2 + i B_33 omega + C_33 ]
//
// The heave RAO is |X|. At low omega the denominator approaches C_33
// and the RAO approaches |F_3| / C_33, which equals 1 in the long-wave
// (Froude-Krylov) limit when F_3 = rho g A_W = C_33. At the undamped
// natural frequency omega_n = sqrt(C_33 / (M + A_33)) the real part of
// the denominator vanishes and the RAO peaks at |F_3| / (B_33 omega_n).
// At high omega the denominator scales as omega^2 and the RAO decays.

const std = @import("std");

pub const Error = error{
    NonPositiveRestoring,
    NonPositiveEffectiveMass,
};

/// Complex number as (re, im).
pub const Complex = struct {
    re: f64,
    im: f64,

    pub fn mag(self: Complex) f64 {
        return @sqrt(self.re * self.re + self.im * self.im);
    }
};

/// Complex response amplitude X(omega) for a unit wave amplitude.
/// Caller supplies F_3(omega) as a complex amplitude.
pub fn responseAmplitude(
    M: f64,
    A_33: f64,
    B_33: f64,
    C_33: f64,
    F_3: Complex,
    omega: f64,
) Error!Complex {
    const m_eff = M + A_33;
    if (m_eff <= 0.0) return Error.NonPositiveEffectiveMass;
    if (C_33 <= 0.0) return Error.NonPositiveRestoring;

    // Denominator: D = -m_eff * omega^2 + i * B_33 * omega + C_33
    const d_re = -m_eff * omega * omega + C_33;
    const d_im = B_33 * omega;

    // X = F / D
    const d_mag_sq = d_re * d_re + d_im * d_im;
    const x_re = (F_3.re * d_re + F_3.im * d_im) / d_mag_sq;
    const x_im = (F_3.im * d_re - F_3.re * d_im) / d_mag_sq;
    return .{ .re = x_re, .im = x_im };
}

/// RAO modulus |X(omega)| per unit wave amplitude.
pub fn raoModulus(
    M: f64,
    A_33: f64,
    B_33: f64,
    C_33: f64,
    F_3: Complex,
    omega: f64,
) Error!f64 {
    const x = try responseAmplitude(M, A_33, B_33, C_33, F_3, omega);
    return x.mag();
}

/// Undamped natural frequency omega_n = sqrt(C_33 / (M + A_33)).
pub fn naturalFrequency(M: f64, A_33: f64, C_33: f64) Error!f64 {
    const m_eff = M + A_33;
    if (m_eff <= 0.0) return Error.NonPositiveEffectiveMass;
    if (C_33 <= 0.0) return Error.NonPositiveRestoring;
    return @sqrt(C_33 / m_eff);
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "Complex.mag matches sqrt(re^2 + im^2)" {
    const c: Complex = .{ .re = 3.0, .im = 4.0 };
    try expectApproxEqAbs(@as(f64, 5.0), c.mag(), 1e-12);
}

test "responseAmplitude at omega = 0 returns F / C_33 (real)" {
    const F: Complex = .{ .re = 1.0, .im = 0.0 };
    const x = try responseAmplitude(1000.0, 500.0, 50.0, 200.0, F, 0.0);
    try expectApproxEqRel(@as(f64, 1.0 / 200.0), x.re, 1e-12);
    try expectApproxEqAbs(@as(f64, 0.0), x.im, 1e-12);
}

test "RAO at long-wave limit approaches 1 when F = C_33 (Froude-Krylov balance)" {
    const M: f64 = 1000.0;
    const A: f64 = 500.0;
    const B: f64 = 50.0;
    const C: f64 = 200.0;
    const F: Complex = .{ .re = C, .im = 0.0 };
    const rao = try raoModulus(M, A, B, C, F, 0.001);
    try expectApproxEqRel(@as(f64, 1.0), rao, 1e-3);
}

test "RAO peaks near the natural frequency" {
    const M: f64 = 1000.0;
    const A: f64 = 500.0;
    const B: f64 = 50.0;
    const C: f64 = 200.0;
    const F: Complex = .{ .re = 1.0, .im = 0.0 };
    const omega_n = try naturalFrequency(M, A, C);
    const rao_peak = try raoModulus(M, A, B, C, F, omega_n);
    const rao_lo = try raoModulus(M, A, B, C, F, 0.5 * omega_n);
    const rao_hi = try raoModulus(M, A, B, C, F, 2.0 * omega_n);
    try std.testing.expect(rao_peak > rao_lo);
    try std.testing.expect(rao_peak > rao_hi);
}

test "RAO at omega_n equals |F| / (B_33 omega_n) within tolerance" {
    const M: f64 = 1000.0;
    const A: f64 = 500.0;
    const B: f64 = 50.0;
    const C: f64 = 200.0;
    const F: Complex = .{ .re = 1.0, .im = 0.0 };
    const omega_n = try naturalFrequency(M, A, C);
    const rao = try raoModulus(M, A, B, C, F, omega_n);
    const expected = 1.0 / (B * omega_n);
    try expectApproxEqRel(expected, rao, 1e-6);
}

test "RAO decays at very high frequency" {
    const M: f64 = 1000.0;
    const A: f64 = 500.0;
    const B: f64 = 50.0;
    const C: f64 = 200.0;
    const F: Complex = .{ .re = 1.0, .im = 0.0 };
    const rao_high = try raoModulus(M, A, B, C, F, 100.0);
    try std.testing.expect(rao_high < 1e-3);
}

test "responseAmplitude rejects non-positive effective mass" {
    const F: Complex = .{ .re = 1.0, .im = 0.0 };
    try std.testing.expectError(Error.NonPositiveEffectiveMass, responseAmplitude(-100.0, 50.0, 10.0, 100.0, F, 1.0));
}

test "responseAmplitude rejects non-positive restoring" {
    const F: Complex = .{ .re = 1.0, .im = 0.0 };
    try std.testing.expectError(Error.NonPositiveRestoring, responseAmplitude(1000.0, 0.0, 10.0, 0.0, F, 1.0));
    try std.testing.expectError(Error.NonPositiveRestoring, responseAmplitude(1000.0, 0.0, 10.0, -1.0, F, 1.0));
}

test "naturalFrequency for known values" {
    // M + A = 1500; C = 600 -> omega_n = sqrt(600 / 1500) = sqrt(0.4) = 0.6325
    const omega_n = try naturalFrequency(1000.0, 500.0, 600.0);
    try expectApproxEqRel(@as(f64, 0.6324555), omega_n, 1e-6);
}

test "RAO magnitude is independent of F phase at fixed |F|" {
    const M: f64 = 1000.0;
    const A: f64 = 500.0;
    const B: f64 = 50.0;
    const C: f64 = 200.0;
    const F1: Complex = .{ .re = 1.0, .im = 0.0 };
    const F2: Complex = .{ .re = 0.0, .im = 1.0 };
    const rao1 = try raoModulus(M, A, B, C, F1, 0.5);
    const rao2 = try raoModulus(M, A, B, C, F2, 0.5);
    try expectApproxEqRel(rao1, rao2, 1e-12);
}

test "RAO is linear in |F|" {
    const M: f64 = 1000.0;
    const A: f64 = 500.0;
    const B: f64 = 50.0;
    const C: f64 = 200.0;
    const F1: Complex = .{ .re = 1.0, .im = 0.0 };
    const F2: Complex = .{ .re = 2.0, .im = 0.0 };
    const rao1 = try raoModulus(M, A, B, C, F1, 0.5);
    const rao2 = try raoModulus(M, A, B, C, F2, 0.5);
    try expectApproxEqRel(@as(f64, 2.0) * rao1, rao2, 1e-12);
}
