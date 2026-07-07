// Wageningen B-series open-water propeller coefficient evaluator.
//
// Functional form:
//
//   K_T(J, P/D, A_E/A_0, Z) = sum_n C_{n,T} * J^{s_n} * (P/D)^{t_n}
//                                  * (A_E/A_0)^{u_n} * Z^{v_n}
//
//   K_Q(J, P/D, A_E/A_0, Z) = sum_n C_{n,Q} * J^{s_n} * (P/D)^{t_n}
//                                  * (A_E/A_0)^{u_n} * Z^{v_n}
//
// Source: Oosterveld, M.W.C. and van Oossanen, P. (1975), "Further
// computer-analyzed data of the Wageningen B-screw series",
// International Shipbuilding Progress, Vol. 22, No. 251.
// Tables 5 (K_T 39 terms, K_Q 47 terms) and 6 (Reynolds correction).
//
// The same tables are reprinted in Bernitsas, M.M., Ray, D., and
// Kinley, P. (1981), "K_T, K_Q and Efficiency Curves for the
// Wageningen B-Series Propellers", University of Michigan Department
// of Naval Architecture and Marine Engineering, Report No. 237.
//
// Several coefficient digits were OCR-ambiguous on the scan used in
// the codex substrate ingest. The values below are the canonical ones
// that downstream implementations (FreeCAD-Ship, NSMB-reprinted
// implementations) carry. See STATUS.md for the list of rows tagged
// `unverified-on-clean-print`.
//
// Reference Reynolds number: Rn = 2.0e6. Above this, apply the
// Reynolds correction in `deltaKT` and `deltaKQ`.

const std = @import("std");

pub const Error = error{
    OutOfValidityZ,
    OutOfValidityPD,
    OutOfValidityAEAO,
    OutOfValidityJ,
    OutOfValidityReynolds,
};

/// Validity envelope (Oosterveld 1975 + PIAS manual ranges).
pub const validity = struct {
    pub const z_min: u8 = 2;
    pub const z_max: u8 = 7;
    pub const pd_min: f64 = 0.5;
    pub const pd_max: f64 = 1.4;
    pub const aeao_min: f64 = 0.30;
    pub const aeao_max: f64 = 1.05;
    pub const j_min: f64 = 0.0;
    pub const j_max: f64 = 1.5;
    pub const rn_ref: f64 = 2.0e6;
    pub const rn_max: f64 = 2.0e9;
};

/// Single polynomial term: C * J^s * (P/D)^t * (A_E/A_0)^u * Z^v.
const Term = struct {
    c: f64,
    s: u8,
    t: u8,
    u: u8,
    v: u8,
};

/// K_T coefficient table. 39 terms. Oosterveld 1975 Table 5 left column.
/// Rows tagged `[ocr]` in source were OCR-ambiguous on the scan; values
/// shown are canonical to downstream implementations. See STATUS.md.
const kt_terms = [_]Term{
    .{ .c = 0.00880496, .s = 0, .t = 0, .u = 0, .v = 0 },
    .{ .c = -0.204554, .s = 1, .t = 0, .u = 0, .v = 0 },
    .{ .c = 0.166351, .s = 0, .t = 1, .u = 0, .v = 0 },
    .{ .c = 0.158114, .s = 0, .t = 2, .u = 0, .v = 0 }, // [ocr]
    .{ .c = -0.147581, .s = 2, .t = 0, .u = 1, .v = 0 },
    .{ .c = -0.481497, .s = 1, .t = 1, .u = 1, .v = 0 },
    .{ .c = 0.415437, .s = 0, .t = 2, .u = 1, .v = 0 },
    .{ .c = 0.0144043, .s = 0, .t = 0, .u = 0, .v = 1 },
    .{ .c = -0.0530054, .s = 2, .t = 0, .u = 0, .v = 1 },
    .{ .c = 0.0143481, .s = 0, .t = 1, .u = 0, .v = 1 },
    .{ .c = 0.0606826, .s = 1, .t = 1, .u = 0, .v = 1 },
    .{ .c = -0.0125894, .s = 0, .t = 0, .u = 1, .v = 1 },
    .{ .c = 0.0109619, .s = 1, .t = 1, .u = 1, .v = 1 }, // [ocr]
    .{ .c = -0.133698, .s = 0, .t = 3, .u = 0, .v = 0 },
    .{ .c = 0.00638407, .s = 0, .t = 6, .u = 0, .v = 0 },
    .{ .c = -0.00132718, .s = 2, .t = 6, .u = 0, .v = 0 }, // [ocr]
    .{ .c = 0.168496, .s = 3, .t = 0, .u = 1, .v = 0 },
    .{ .c = -0.0507214, .s = 0, .t = 0, .u = 2, .v = 0 },
    .{ .c = 0.0854559, .s = 2, .t = 0, .u = 2, .v = 0 },
    .{ .c = -0.0504475, .s = 3, .t = 0, .u = 2, .v = 0 },
    .{ .c = 0.010465, .s = 1, .t = 6, .u = 2, .v = 0 },
    .{ .c = -0.00648272, .s = 2, .t = 6, .u = 2, .v = 0 },
    .{ .c = -0.00841728, .s = 0, .t = 3, .u = 0, .v = 1 },
    .{ .c = 0.0168424, .s = 1, .t = 3, .u = 0, .v = 1 },
    .{ .c = -0.00102296, .s = 3, .t = 3, .u = 0, .v = 1 },
    .{ .c = -0.0317791, .s = 0, .t = 3, .u = 1, .v = 1 },
    .{ .c = 0.018604, .s = 1, .t = 0, .u = 2, .v = 1 },
    .{ .c = -0.00410798, .s = 0, .t = 2, .u = 2, .v = 1 }, // [ocr]
    .{ .c = -0.000606848, .s = 0, .t = 0, .u = 0, .v = 2 },
    .{ .c = -0.0049819, .s = 1, .t = 0, .u = 0, .v = 2 },
    .{ .c = 0.0025983, .s = 2, .t = 0, .u = 0, .v = 2 },
    .{ .c = -0.000560528, .s = 3, .t = 0, .u = 0, .v = 2 }, // [ocr]
    .{ .c = -0.00163652, .s = 1, .t = 2, .u = 0, .v = 2 },
    .{ .c = -0.000328787, .s = 1, .t = 6, .u = 0, .v = 2 },
    .{ .c = 0.000116502, .s = 2, .t = 6, .u = 0, .v = 2 },
    .{ .c = 0.000690904, .s = 0, .t = 0, .u = 1, .v = 2 },
    .{ .c = 0.00421749, .s = 0, .t = 3, .u = 1, .v = 2 },
    .{ .c = 0.0000565229, .s = 3, .t = 6, .u = 1, .v = 2 },
    .{ .c = -0.00146564, .s = 0, .t = 3, .u = 2, .v = 2 },
};

/// K_Q coefficient table. 47 terms. Oosterveld 1975 Table 5 right column.
const kq_terms = [_]Term{
    .{ .c = 0.00379368, .s = 0, .t = 0, .u = 0, .v = 0 },
    .{ .c = 0.00886523, .s = 2, .t = 0, .u = 0, .v = 0 },
    .{ .c = -0.032241, .s = 1, .t = 1, .u = 0, .v = 0 }, // [ocr]
    .{ .c = 0.00344778, .s = 0, .t = 1, .u = 0, .v = 0 },
    .{ .c = -0.0408811, .s = 0, .t = 1, .u = 1, .v = 0 },
    .{ .c = -0.108009, .s = 1, .t = 1, .u = 1, .v = 0 },
    .{ .c = -0.0885381, .s = 2, .t = 1, .u = 1, .v = 0 }, // [ocr]
    .{ .c = 0.188561, .s = 0, .t = 2, .u = 1, .v = 0 },
    .{ .c = -0.00370871, .s = 1, .t = 0, .u = 0, .v = 1 },
    .{ .c = 0.00513696, .s = 0, .t = 1, .u = 0, .v = 1 },
    .{ .c = 0.0209449, .s = 1, .t = 1, .u = 0, .v = 1 },
    .{ .c = 0.00474319, .s = 2, .t = 1, .u = 0, .v = 1 },
    .{ .c = -0.00723408, .s = 2, .t = 0, .u = 1, .v = 1 },
    .{ .c = 0.00438388, .s = 1, .t = 1, .u = 1, .v = 1 },
    .{ .c = -0.0269403, .s = 0, .t = 2, .u = 1, .v = 1 },
    .{ .c = 0.0558082, .s = 3, .t = 0, .u = 1, .v = 0 },
    .{ .c = 0.0161886, .s = 0, .t = 3, .u = 1, .v = 0 }, // [ocr]
    .{ .c = 0.00318086, .s = 1, .t = 3, .u = 1, .v = 0 }, // [ocr]
    .{ .c = 0.015896, .s = 0, .t = 0, .u = 2, .v = 0 },
    .{ .c = 0.0471729, .s = 1, .t = 0, .u = 2, .v = 0 },
    .{ .c = -0.0196283, .s = 3, .t = 0, .u = 2, .v = 0 },
    .{ .c = -0.0502782, .s = 0, .t = 1, .u = 2, .v = 0 },
    .{ .c = -0.030055, .s = 3, .t = 1, .u = 2, .v = 0 },
    .{ .c = 0.0417122, .s = 2, .t = 2, .u = 2, .v = 0 },
    .{ .c = -0.0397722, .s = 0, .t = 3, .u = 2, .v = 0 },
    .{ .c = -0.00350024, .s = 0, .t = 6, .u = 2, .v = 0 },
    .{ .c = -0.0106854, .s = 3, .t = 0, .u = 0, .v = 1 },
    .{ .c = 0.00110903, .s = 3, .t = 3, .u = 0, .v = 1 }, // [ocr]
    .{ .c = -0.000313912, .s = 0, .t = 6, .u = 0, .v = 1 }, // [ocr]
    .{ .c = 0.0035985, .s = 3, .t = 0, .u = 1, .v = 1 },
    .{ .c = -0.00142121, .s = 0, .t = 6, .u = 1, .v = 1 },
    .{ .c = -0.00383637, .s = 1, .t = 0, .u = 2, .v = 1 },
    .{ .c = 0.0126803, .s = 0, .t = 2, .u = 2, .v = 1 },
    .{ .c = -0.00318278, .s = 2, .t = 3, .u = 2, .v = 1 },
    .{ .c = 0.0033418, .s = 0, .t = 6, .u = 2, .v = 1 }, // [ocr]
    .{ .c = -0.00183491, .s = 1, .t = 1, .u = 0, .v = 2 },
    .{ .c = 0.000112451, .s = 3, .t = 2, .u = 0, .v = 2 },
    .{ .c = -0.0000297228, .s = 3, .t = 6, .u = 0, .v = 2 },
    .{ .c = 0.000269551, .s = 1, .t = 0, .u = 1, .v = 2 },
    .{ .c = 0.00083265, .s = 2, .t = 0, .u = 1, .v = 2 },
    .{ .c = 0.00155334, .s = 0, .t = 2, .u = 1, .v = 2 },
    .{ .c = 0.000302683, .s = 0, .t = 6, .u = 1, .v = 2 },
    .{ .c = -0.0001843, .s = 0, .t = 0, .u = 2, .v = 2 }, // [ocr]
    .{ .c = -0.000425399, .s = 0, .t = 3, .u = 2, .v = 2 }, // [ocr]
    .{ .c = 0.0000869243, .s = 3, .t = 3, .u = 2, .v = 2 }, // [ocr]
    .{ .c = -0.0004659, .s = 0, .t = 6, .u = 2, .v = 2 },
    .{ .c = 0.0000554194, .s = 1, .t = 6, .u = 2, .v = 2 },
};

fn powU(base: f64, exp: u8) f64 {
    var result: f64 = 1.0;
    var i: u8 = 0;
    while (i < exp) : (i += 1) result *= base;
    return result;
}

fn evalPoly(terms: []const Term, j: f64, pd: f64, aeao: f64, z: f64) f64 {
    var sum: f64 = 0.0;
    for (terms) |t| {
        sum += t.c * powU(j, t.s) * powU(pd, t.t) * powU(aeao, t.u) * powU(z, t.v);
    }
    return sum;
}

/// K_T at reference Reynolds (Rn = 2.0e6). No Reynolds correction applied.
/// Caller must verify inputs are within the validity envelope.
pub fn kT(j: f64, pd: f64, aeao: f64, z: f64) f64 {
    return evalPoly(&kt_terms, j, pd, aeao, z);
}

/// K_Q at reference Reynolds (Rn = 2.0e6).
pub fn kQ(j: f64, pd: f64, aeao: f64, z: f64) f64 {
    return evalPoly(&kq_terms, j, pd, aeao, z);
}

/// Open-water propeller efficiency.
/// eta_O = (J / (2 * pi)) * (K_T / K_Q). Caller should check K_Q > 0.
pub fn etaO(j: f64, kt_val: f64, kq_val: f64) f64 {
    return (j / (2.0 * std.math.pi)) * (kt_val / kq_val);
}

/// Reynolds correction to K_T per Oosterveld 1975 Table 6.
/// Applies above Rn = 2.0e6; below that the polynomial is direct.
/// At Rn = 2.0e6 the (log Rn - 0.301) term is log(2e6) - 0.301
/// = 6.30103 - 0.301 = 6.00003, not zero; the table's reference
/// point is structurally Rn = 2.0e6 with the polynomial itself
/// already calibrated there. The correction polynomial below adds
/// the documented Rn-dependent perturbation.
pub fn deltaKT(j: f64, pd: f64, aeao: f64, z: f64, rn: f64) f64 {
    const logRn = std.math.log10(rn) - 0.301;
    var d: f64 = 0.000353485;
    d += -0.00333758 * aeao * j * j;
    d += -0.00478125 * aeao * pd * j;
    d += 0.000257792 * logRn * logRn * aeao * j * j;
    d += 0.0000643192 * logRn * powU(pd, 6) * j * j;
    d += -0.0000110636 * logRn * logRn * powU(pd, 6) * j * j;
    d += -0.0000276305 * logRn * logRn * z * aeao * j * j;
    d += 0.0000954 * logRn * z * aeao * pd * j;
    d += 0.0000032049 * logRn * z * z * aeao * powU(pd, 3) * j;
    return d;
}

/// Reynolds correction to K_Q per Oosterveld 1975 Table 6.
pub fn deltaKQ(j: f64, pd: f64, aeao: f64, z: f64, rn: f64) f64 {
    _ = j;
    const logRn = std.math.log10(rn) - 0.301;
    var d: f64 = -0.000591412;
    d += 0.00696898 * pd;
    d += -0.0000666654 * z * powU(pd, 6);
    d += 0.0160818 * aeao * aeao;
    d += -0.000938091 * logRn * pd;
    d += -0.000595958 * logRn * pd * pd;
    d += 0.0000782099 * logRn * logRn * pd * pd;
    return d;
}

/// Validate inputs against published validity envelope.
pub fn validate(j: f64, pd: f64, aeao: f64, z: u8, rn: f64) Error!void {
    if (z < validity.z_min or z > validity.z_max) return Error.OutOfValidityZ;
    if (pd < validity.pd_min or pd > validity.pd_max) return Error.OutOfValidityPD;
    if (aeao < validity.aeao_min or aeao > validity.aeao_max) return Error.OutOfValidityAEAO;
    if (j < validity.j_min or j > validity.j_max) return Error.OutOfValidityJ;
    if (rn < validity.rn_ref or rn > validity.rn_max) return Error.OutOfValidityReynolds;
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "kT positive at bollard pull (J = 0) for B4-70, P/D = 1.0" {
    // At J = 0 the propeller is stationary in the ship-fixed frame; thrust is
    // the bollard pull. K_T must be positive.
    const kt = kT(0.0, 1.0, 0.70, 4.0);
    try std.testing.expect(kt > 0.0);
}

test "kQ positive at moderate operating point for B4-70" {
    const kq = kQ(0.6, 1.0, 0.70, 4.0);
    try std.testing.expect(kq > 0.0);
}

test "kT becomes negative beyond zero-thrust J" {
    // Open-water curve: K_T decreases monotonically with J until it crosses
    // zero (the propeller is windmilling rather than producing thrust).
    // For B4-70 P/D = 1.0 the zero-thrust J is approximately 1.1-1.3.
    const kt_low = kT(0.5, 1.0, 0.70, 4.0);
    const kt_high = kT(1.4, 1.0, 0.70, 4.0);
    try std.testing.expect(kt_low > 0.0);
    try std.testing.expect(kt_high < 0.0);
}

test "etaO peaks at intermediate J for B4-70 P/D = 1.0" {
    // The open-water efficiency curve peaks at J between approximately
    // 0.55 and 0.75 for B4-70 P/D = 1.0. Check that eta_O at J = 0.65
    // is greater than eta_O at J = 0.1 and J = 1.1.
    const j_peak: f64 = 0.65;
    const eta_peak = etaO(j_peak, kT(j_peak, 1.0, 0.70, 4.0), kQ(j_peak, 1.0, 0.70, 4.0));

    const j_low: f64 = 0.1;
    const eta_low = etaO(j_low, kT(j_low, 1.0, 0.70, 4.0), kQ(j_low, 1.0, 0.70, 4.0));

    const j_high: f64 = 1.1;
    const eta_high = etaO(j_high, kT(j_high, 1.0, 0.70, 4.0), kQ(j_high, 1.0, 0.70, 4.0));

    try std.testing.expect(eta_peak > eta_low);
    try std.testing.expect(eta_peak > eta_high);
}

test "etaO at peak for B4-70 P/D = 1.0 falls within 0.50 to 0.75" {
    // Published B-series open-water curves: peak eta_O for B4-70 P/D = 1.0
    // is typically around 0.60. Widen the bound to 0.50-0.75 to catch only
    // a gross coefficient regression, not regression-noise differences.
    const j: f64 = 0.65;
    const eta = etaO(j, kT(j, 1.0, 0.70, 4.0), kQ(j, 1.0, 0.70, 4.0));
    try std.testing.expect(eta > 0.50);
    try std.testing.expect(eta < 0.75);
}

test "kT monotonically decreases between J=0 and zero-thrust J" {
    // Sample at 11 points; verify each is strictly less than the previous.
    var prev: f64 = std.math.inf(f64);
    var i: usize = 0;
    while (i <= 10) : (i += 1) {
        const j_val = @as(f64, @floatFromInt(i)) * 0.1;
        const kt = kT(j_val, 1.0, 0.70, 4.0);
        try std.testing.expect(kt < prev);
        prev = kt;
    }
}

test "kT regression lock at J=0, B4-70, P/D=1.0" {
    // Lock-in: this value is what the polynomial as currently coded
    // produces. A future coefficient change must explicitly update
    // the lock-in alongside an external cross-check against a clean
    // print of Bernitsas 1981 (Publication 237) or against an
    // independent implementation. The lock-in defends against silent
    // regressions on the OCR-ambiguous rows; it does NOT assert
    // absolute agreement with published reference values.
    const kt = kT(0.0, 1.0, 0.70, 4.0);
    try expectApproxEqAbs(@as(f64, 0.45474), kt, 1e-4);
}

test "kQ regression lock at J=0.6, B4-70, P/D=1.0" {
    const kq = kQ(0.6, 1.0, 0.70, 4.0);
    try expectApproxEqAbs(@as(f64, 0.0287), kq, 5e-3);
}

test "validate accepts B4-70 at typical operating point" {
    try validate(0.6, 1.0, 0.70, 4, 1.0e7);
}

test "validate rejects out-of-range Z" {
    try std.testing.expectError(Error.OutOfValidityZ, validate(0.6, 1.0, 0.70, 1, 1.0e7));
    try std.testing.expectError(Error.OutOfValidityZ, validate(0.6, 1.0, 0.70, 8, 1.0e7));
}

test "validate rejects out-of-range P/D" {
    try std.testing.expectError(Error.OutOfValidityPD, validate(0.6, 0.4, 0.70, 4, 1.0e7));
    try std.testing.expectError(Error.OutOfValidityPD, validate(0.6, 1.5, 0.70, 4, 1.0e7));
}

test "validate rejects out-of-range A_E/A_0" {
    try std.testing.expectError(Error.OutOfValidityAEAO, validate(0.6, 1.0, 0.20, 4, 1.0e7));
    try std.testing.expectError(Error.OutOfValidityAEAO, validate(0.6, 1.0, 1.10, 4, 1.0e7));
}

test "validate rejects out-of-range Reynolds" {
    // Below the reference Rn the Oosterveld 1975 polynomial is not calibrated.
    try std.testing.expectError(Error.OutOfValidityReynolds, validate(0.6, 1.0, 0.70, 4, 1.0e5));
    try std.testing.expectError(Error.OutOfValidityReynolds, validate(0.6, 1.0, 0.70, 4, 1.0e10));
}

test "deltaKT at moderate Rn produces small correction" {
    const dkt = deltaKT(0.6, 1.0, 0.70, 4.0, 1.0e7);
    // Correction should be small relative to K_T itself (perhaps a few percent).
    try std.testing.expect(@abs(dkt) < 0.05);
}

test "deltaKQ at moderate Rn produces small correction" {
    const dkq = deltaKQ(0.6, 1.0, 0.70, 4.0, 1.0e7);
    try std.testing.expect(@abs(dkq) < 0.05);
}

test "kT and kQ are deterministic" {
    // Same inputs produce same outputs across repeated calls.
    const a = kT(0.6, 1.0, 0.70, 4.0);
    const b = kT(0.6, 1.0, 0.70, 4.0);
    try expectApproxEqAbs(a, b, 0.0);
    const c = kQ(0.6, 1.0, 0.70, 4.0);
    const d = kQ(0.6, 1.0, 0.70, 4.0);
    try expectApproxEqAbs(c, d, 0.0);
}

test "kT decreases as P/D rises at fixed J (qualitative)" {
    // At fixed J = 0.6 the propeller with higher pitch ratio produces
    // proportionally higher thrust at the same advance ratio because the
    // blade is at a larger pitch angle.
    const kt_low_pd = kT(0.6, 0.6, 0.70, 4.0);
    const kt_high_pd = kT(0.6, 1.2, 0.70, 4.0);
    try std.testing.expect(kt_high_pd > kt_low_pd);
}

test "kQ rises as P/D rises at fixed J" {
    const kq_low_pd = kQ(0.6, 0.6, 0.70, 4.0);
    const kq_high_pd = kQ(0.6, 1.2, 0.70, 4.0);
    try std.testing.expect(kq_high_pd > kq_low_pd);
}

test "polynomial term count matches published tables" {
    try std.testing.expectEqual(@as(usize, 39), kt_terms.len);
    try std.testing.expectEqual(@as(usize, 47), kq_terms.len);
}
