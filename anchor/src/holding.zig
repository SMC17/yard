const std = @import("std");

pub const Error = error{
    NonPositiveAnchorWeight,
    NonPositiveChainWeight,
    NonPositiveLength,
    InvalidKFactor,
};

pub const AnchorType = enum {
    /// Standard high-holding-power anchor per IACS A1; K_anchor = 1.0
    /// in the empirical fit (i.e. the unscaled baseline).
    Standard,
    /// HHP (High Holding Power) per IACS A1; K_anchor = 1.3.
    HHP,
    /// SHHP (Super High Holding Power) per IACS A1; K_anchor = 1.7.
    SHHP,

    pub fn kFactor(self: AnchorType) f64 {
        return switch (self) {
            .Standard => 1.0,
            .HHP => 1.3,
            .SHHP => 1.7,
        };
    }
};

/// Anchor holding power in kN per the Stevin empirical regression:
///   H_max = K * W^(0.92)
/// with W in kN of anchor mass-equivalent weight.
pub fn anchorHoldingKN(anchor_weight_kn: f64, atype: AnchorType) Error!f64 {
    if (!(anchor_weight_kn > 0)) return Error.NonPositiveAnchorWeight;
    return atype.kFactor() * std.math.pow(f64, anchor_weight_kn, 0.92);
}

/// Chain holding contribution from the length of chain lying on the
/// seabed under friction coefficient mu:
///   H_chain = mu * w_chain * L_floor
/// where w_chain is the weight per unit length [kN/m] and L_floor is
/// the on-bottom chain length [m]. Default mu = 1.0 (sand / mud per
/// API RP 2SK long-term static).
pub fn chainSeabedHoldingKN(
    mu: f64,
    w_chain_kn_per_m: f64,
    L_floor_m: f64,
) Error!f64 {
    if (!(mu > 0)) return Error.InvalidKFactor;
    if (!(w_chain_kn_per_m > 0)) return Error.NonPositiveChainWeight;
    if (!(L_floor_m > 0)) return Error.NonPositiveLength;
    return mu * w_chain_kn_per_m * L_floor_m;
}

/// Total horizontal holding force [kN]:
///   H_total = H_anchor + H_chain.
pub fn totalHoldingKN(
    anchor_weight_kn: f64,
    atype: AnchorType,
    mu: f64,
    w_chain_kn_per_m: f64,
    L_floor_m: f64,
) Error!f64 {
    const H_a = try anchorHoldingKN(anchor_weight_kn, atype);
    const H_c = try chainSeabedHoldingKN(mu, w_chain_kn_per_m, L_floor_m);
    return H_a + H_c;
}

test "anchor holding for standard 100 kN anchor" {
    // 1.0 * 100^0.92 = 1.0 * 67.6 = 67.6 kN.
    const H = try anchorHoldingKN(100.0, .Standard);
    const expected = std.math.pow(f64, 100.0, 0.92);
    try std.testing.expectApproxEqAbs(expected, H, 1e-9);
}

test "HHP gives 1.3x the standard holding" {
    const H_std = try anchorHoldingKN(100.0, .Standard);
    const H_hhp = try anchorHoldingKN(100.0, .HHP);
    try std.testing.expectApproxEqAbs(1.3 * H_std, H_hhp, 1e-9);
}

test "SHHP gives 1.7x the standard holding" {
    const H_std = try anchorHoldingKN(100.0, .Standard);
    const H_shhp = try anchorHoldingKN(100.0, .SHHP);
    try std.testing.expectApproxEqAbs(1.7 * H_std, H_shhp, 1e-9);
}

test "anchor holding scales sublinearly: W x 2 < H x 2" {
    const H1 = try anchorHoldingKN(100.0, .Standard);
    const H2 = try anchorHoldingKN(200.0, .Standard);
    // Power 0.92 < 1 -> ratio is 2^0.92 ~ 1.893.
    const ratio = std.math.pow(f64, 2.0, 0.92);
    try std.testing.expectApproxEqAbs(ratio * H1, H2, 1e-9);
}

test "chain seabed holding: mu = 1, w = 1 kN/m, L = 50 m = 50 kN" {
    const H = try chainSeabedHoldingKN(1.0, 1.0, 50.0);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), H, 1e-12);
}

test "chain holding linear in mu, w, and L" {
    const H1 = try chainSeabedHoldingKN(1.0, 1.0, 50.0);
    const H_mu2 = try chainSeabedHoldingKN(2.0, 1.0, 50.0);
    const H_w2 = try chainSeabedHoldingKN(1.0, 2.0, 50.0);
    const H_L2 = try chainSeabedHoldingKN(1.0, 1.0, 100.0);
    try std.testing.expectApproxEqAbs(2.0 * H1, H_mu2, 1e-9);
    try std.testing.expectApproxEqAbs(2.0 * H1, H_w2, 1e-9);
    try std.testing.expectApproxEqAbs(2.0 * H1, H_L2, 1e-9);
}

test "total holding sums anchor + chain contributions" {
    const H_total = try totalHoldingKN(100.0, .HHP, 1.0, 1.0, 50.0);
    const H_a = try anchorHoldingKN(100.0, .HHP);
    const H_c = try chainSeabedHoldingKN(1.0, 1.0, 50.0);
    try std.testing.expectApproxEqAbs(H_a + H_c, H_total, 1e-9);
}

test "input rejection: zero anchor weight" {
    try std.testing.expectError(Error.NonPositiveAnchorWeight, anchorHoldingKN(0.0, .Standard));
}

test "input rejection: zero friction coefficient" {
    try std.testing.expectError(Error.InvalidKFactor, chainSeabedHoldingKN(0.0, 1.0, 50.0));
}

test "input rejection: zero L_floor" {
    try std.testing.expectError(Error.NonPositiveLength, chainSeabedHoldingKN(1.0, 1.0, 0.0));
}
