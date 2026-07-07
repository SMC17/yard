const std = @import("std");

pub const Error = error{
    NonPositiveLength,
    NonPositiveDepth,
    InvalidModeIndex,
    NonPositiveGravity,
};

/// Antisymmetric horizontal-sloshing wave number for mode n:
///   k_n = (2 n + 1) pi / L
pub fn waveNumberAntisymmetric(n: u32, L_m: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    const m: f64 = @floatFromInt(2 * n + 1);
    return m * std.math.pi / L_m;
}

/// Symmetric sloshing wave number for mode n (heave / surge excitation):
///   k_n = 2 n pi / L for n >= 1
pub fn waveNumberSymmetric(n: u32, L_m: f64) Error!f64 {
    if (n == 0) return Error.InvalidModeIndex;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    const m: f64 = @floatFromInt(2 * n);
    return m * std.math.pi / L_m;
}

/// Natural angular frequency of mode `k`:
///   omega = sqrt(g k tanh(k h))
pub fn naturalAngularFrequency(k_m_inv: f64, h_m: f64, g_mps2: f64) Error!f64 {
    if (!(h_m > 0)) return Error.NonPositiveDepth;
    if (!(g_mps2 > 0)) return Error.NonPositiveGravity;
    return @sqrt(g_mps2 * k_m_inv * std.math.tanh(k_m_inv * h_m));
}

/// Natural period T = 2 pi / omega.
pub fn naturalPeriodSec(omega: f64) f64 {
    return 2.0 * std.math.pi / omega;
}

/// Fundamental antisymmetric-mode natural angular frequency for a
/// rectangular tank of length `L` (along the sway axis) and fluid
/// depth `h`. Special case of the general formula at n = 0.
pub fn fundamentalAntisymmetricRectangular(L_m: f64, h_m: f64, g_mps2: f64) Error!f64 {
    const k0 = try waveNumberAntisymmetric(0, L_m);
    return try naturalAngularFrequency(k0, h_m, g_mps2);
}

/// Deep-water limit: when k h is large, tanh(k h) -> 1 and
///   omega -> sqrt(g k).
pub fn deepWaterLimitOmega(k_m_inv: f64, g_mps2: f64) Error!f64 {
    if (!(g_mps2 > 0)) return Error.NonPositiveGravity;
    return @sqrt(g_mps2 * k_m_inv);
}

/// Shallow-water limit: when k h is small, tanh(k h) -> k h and
///   omega -> k sqrt(g h).
pub fn shallowWaterLimitOmega(k_m_inv: f64, h_m: f64, g_mps2: f64) Error!f64 {
    if (!(h_m > 0)) return Error.NonPositiveDepth;
    if (!(g_mps2 > 0)) return Error.NonPositiveGravity;
    return k_m_inv * @sqrt(g_mps2 * h_m);
}

test "antisymmetric wave numbers k_0 = pi/L, k_1 = 3 pi / L" {
    try std.testing.expectApproxEqAbs(
        std.math.pi / 10.0,
        try waveNumberAntisymmetric(0, 10.0),
        1e-12,
    );
    try std.testing.expectApproxEqAbs(
        3.0 * std.math.pi / 10.0,
        try waveNumberAntisymmetric(1, 10.0),
        1e-12,
    );
}

test "symmetric wave numbers k_1 = 2 pi / L, k_2 = 4 pi / L" {
    try std.testing.expectApproxEqAbs(
        2.0 * std.math.pi / 10.0,
        try waveNumberSymmetric(1, 10.0),
        1e-12,
    );
    try std.testing.expectApproxEqAbs(
        4.0 * std.math.pi / 10.0,
        try waveNumberSymmetric(2, 10.0),
        1e-12,
    );
}

test "symmetric mode n=0 rejected" {
    try std.testing.expectError(
        Error.InvalidModeIndex,
        waveNumberSymmetric(0, 10.0),
    );
}

test "fundamental antisymmetric mode at L=10, h=5, g=9.81" {
    const omega = try fundamentalAntisymmetricRectangular(10.0, 5.0, 9.81);
    const k0 = std.math.pi / 10.0;
    const expected = @sqrt(9.81 * k0 * std.math.tanh(@as(f64, k0 * 5.0)));
    try std.testing.expectApproxEqAbs(expected, omega, 1e-12);
}

test "natural period closed form" {
    const T = naturalPeriodSec(2.0);
    try std.testing.expectApproxEqAbs(std.math.pi, T, 1e-12);
}

test "deep-water limit: omega -> sqrt(g k) as h -> infinity" {
    const k0 = std.math.pi / 10.0;
    const omega_inf = try deepWaterLimitOmega(k0, 9.81);
    const omega_finite = try naturalAngularFrequency(k0, 100.0, 9.81);
    try std.testing.expectApproxEqAbs(omega_inf, omega_finite, 1e-6);
}

test "shallow-water limit: omega -> k sqrt(g h) as h -> 0" {
    const k0 = std.math.pi / 10.0;
    const h: f64 = 0.005; // very shallow
    const omega_shallow = try shallowWaterLimitOmega(k0, h, 9.81);
    const omega_finite = try naturalAngularFrequency(k0, h, 9.81);
    const rel = @abs(omega_shallow - omega_finite) / omega_shallow;
    try std.testing.expect(rel < 1e-4);
}

test "higher modes have higher natural frequencies" {
    const k0 = try waveNumberAntisymmetric(0, 10.0);
    const k1 = try waveNumberAntisymmetric(1, 10.0);
    const k2 = try waveNumberAntisymmetric(2, 10.0);
    const o0 = try naturalAngularFrequency(k0, 5.0, 9.81);
    const o1 = try naturalAngularFrequency(k1, 5.0, 9.81);
    const o2 = try naturalAngularFrequency(k2, 5.0, 9.81);
    try std.testing.expect(o1 > o0);
    try std.testing.expect(o2 > o1);
}

test "Faltinsen Section 4.3.1 worked example: L=1.73, h=0.6, g=9.81" {
    // From Faltinsen and Timokha (2009) Section 4.3.1 worked example.
    // omega_1 = pi (g / L) tanh(pi h / L) -- but for the squared form.
    // omega_1^2 = g (pi/L) tanh(pi h / L) where pi/L = 1.8157,
    // tanh(pi * 0.6 / 1.73) = tanh(1.0894) = 0.7967.
    // omega_1^2 = 9.81 * 1.8157 * 0.7967 = 14.193 -> omega_1 = 3.768.
    const omega = try fundamentalAntisymmetricRectangular(1.73, 0.6, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 3.768), omega, 0.01);
}

test "non-positive length rejected" {
    try std.testing.expectError(Error.NonPositiveLength, waveNumberAntisymmetric(0, 0.0));
}

test "non-positive depth rejected" {
    const k = try waveNumberAntisymmetric(0, 10.0);
    try std.testing.expectError(Error.NonPositiveDepth, naturalAngularFrequency(k, 0.0, 9.81));
}
