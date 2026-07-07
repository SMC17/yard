// KN cross-curves and full GZ-curve integration.
//
// At the design stage the GZ curve at the actual KG is reconstructed
// from the KN cross-curves of stability (KN values precomputed at
// fixed displacement increments and at heel angles 0, 10, 20, ...,
// 80 deg) via:
//   GZ(phi) = KN(phi) - KG sin(phi)
// Dynamic stability (area under GZ) is integrated by Simpson's 1/3
// rule on the same angle grid.

const std = @import("std");

pub const Error = error{
    NonPositiveKG,
    NegativeKN,
    InvalidAngle,
    UnequalLength,
    InsufficientPoints,
};

/// Standard IMO IS Code angle grid for KN tabulation [deg].
pub const standard_angles_deg = [_]f64{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };

/// GZ at heel `phi` from KN cross-curve value and KG:
///   GZ(phi) = KN(phi) - KG sin(phi).
pub fn gzFromKN(KN_phi_m: f64, KG_m: f64, phi_rad: f64) Error!f64 {
    if (!(KG_m > 0)) return Error.NonPositiveKG;
    if (!(KN_phi_m >= 0)) return Error.NegativeKN;
    if (!(phi_rad >= 0 and phi_rad <= std.math.pi)) return Error.InvalidAngle;
    return KN_phi_m - KG_m * @sin(phi_rad);
}

/// Build the GZ array from a KN array tabulated at `angles_deg`.
pub fn buildGZArrayM(
    KN_arr_m: []const f64,
    angles_deg: []const f64,
    KG_m: f64,
    GZ_out_m: []f64,
) Error!void {
    if (KN_arr_m.len != angles_deg.len) return Error.UnequalLength;
    if (GZ_out_m.len != KN_arr_m.len) return Error.UnequalLength;
    if (!(KG_m > 0)) return Error.NonPositiveKG;
    const deg = std.math.pi / 180.0;
    for (KN_arr_m, angles_deg, 0..) |KN, ang, i| {
        if (!(ang >= 0 and ang <= 180)) return Error.InvalidAngle;
        if (!(KN >= 0)) return Error.NegativeKN;
        GZ_out_m[i] = KN - KG_m * @sin(ang * deg);
    }
}

/// Linear interpolation of GZ at an arbitrary heel angle from the
/// tabulated GZ array.
pub fn gzAtAngleM(
    GZ_arr_m: []const f64,
    angles_deg: []const f64,
    phi_deg: f64,
) Error!f64 {
    if (GZ_arr_m.len != angles_deg.len) return Error.UnequalLength;
    if (GZ_arr_m.len < 2) return Error.InsufficientPoints;
    if (phi_deg < angles_deg[0]) return GZ_arr_m[0];
    if (phi_deg >= angles_deg[angles_deg.len - 1]) return GZ_arr_m[GZ_arr_m.len - 1];
    var i: usize = 0;
    while (i + 1 < angles_deg.len) : (i += 1) {
        if (phi_deg >= angles_deg[i] and phi_deg <= angles_deg[i + 1]) {
            const t = (phi_deg - angles_deg[i]) /
                (angles_deg[i + 1] - angles_deg[i]);
            return GZ_arr_m[i] * (1.0 - t) + GZ_arr_m[i + 1] * t;
        }
    }
    return GZ_arr_m[GZ_arr_m.len - 1];
}

/// Maximum GZ over the tabulated curve.
pub fn maxGZM(GZ_arr_m: []const f64) Error!f64 {
    if (GZ_arr_m.len == 0) return Error.InsufficientPoints;
    var max = GZ_arr_m[0];
    for (GZ_arr_m[1..]) |v| if (v > max) {
        max = v;
    };
    return max;
}

/// Angle of maximum GZ in degrees, interpolated.
pub fn angleOfMaxGZDeg(
    GZ_arr_m: []const f64,
    angles_deg: []const f64,
) Error!f64 {
    if (GZ_arr_m.len != angles_deg.len) return Error.UnequalLength;
    if (GZ_arr_m.len == 0) return Error.InsufficientPoints;
    var i_max: usize = 0;
    var max = GZ_arr_m[0];
    for (GZ_arr_m, 0..) |v, i| {
        if (v > max) {
            max = v;
            i_max = i;
        }
    }
    return angles_deg[i_max];
}

/// Range of positive stability: largest angle phi such that GZ > 0,
/// measured from the upright position. Linearly interpolates the
/// zero-crossing between the last positive and the first non-positive
/// tabulated value.
pub fn rangeOfStabilityDeg(
    GZ_arr_m: []const f64,
    angles_deg: []const f64,
) Error!f64 {
    if (GZ_arr_m.len != angles_deg.len) return Error.UnequalLength;
    if (GZ_arr_m.len < 2) return Error.InsufficientPoints;
    var i: usize = 1;
    while (i < GZ_arr_m.len) : (i += 1) {
        if (GZ_arr_m[i] <= 0 and GZ_arr_m[i - 1] > 0) {
            // Linear interpolation to GZ = 0.
            const t = GZ_arr_m[i - 1] / (GZ_arr_m[i - 1] - GZ_arr_m[i]);
            return angles_deg[i - 1] + t *
                (angles_deg[i] - angles_deg[i - 1]);
        }
    }
    return angles_deg[angles_deg.len - 1];
}

/// Dynamic stability: area under the GZ curve from 0 to a given
/// angle in radians, via Simpson's 1/3 rule. Requires an odd number
/// of grid points (8 intervals for the standard 9-point IMO grid).
pub fn dynamicStabilityMRad(
    GZ_arr_m: []const f64,
    angles_deg: []const f64,
    up_to_deg: f64,
) Error!f64 {
    if (GZ_arr_m.len != angles_deg.len) return Error.UnequalLength;
    if (GZ_arr_m.len < 3) return Error.InsufficientPoints;
    const deg = std.math.pi / 180.0;
    // Find the index where angles_deg <= up_to_deg.
    var n_use: usize = 0;
    while (n_use < angles_deg.len and angles_deg[n_use] <= up_to_deg) {
        n_use += 1;
    }
    if (n_use < 2) return 0.0;
    // Simpson 1/3 on the first n_use points if (n_use - 1) is even,
    // else fall back to trapezoidal rule.
    const h = (angles_deg[1] - angles_deg[0]) * deg;
    if ((n_use - 1) % 2 == 0 and n_use >= 3) {
        var sum: f64 = GZ_arr_m[0] + GZ_arr_m[n_use - 1];
        var k: usize = 1;
        while (k < n_use - 1) : (k += 1) {
            if (k % 2 == 1) {
                sum += 4.0 * GZ_arr_m[k];
            } else {
                sum += 2.0 * GZ_arr_m[k];
            }
        }
        return sum * h / 3.0;
    } else {
        // Trapezoidal rule on the partial range.
        var sum: f64 = 0.5 * (GZ_arr_m[0] + GZ_arr_m[n_use - 1]);
        var k: usize = 1;
        while (k < n_use - 1) : (k += 1) {
            sum += GZ_arr_m[k];
        }
        return sum * h;
    }
}

test "GZ from KN at phi = 0 equals KN(0)" {
    const gz = try gzFromKN(0.0, 8.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), gz, 1e-12);
}

test "GZ from KN: KG sin(phi) reduction" {
    const phi = std.math.pi / 6.0;
    const gz = try gzFromKN(4.5, 8.0, phi);
    try std.testing.expectApproxEqAbs(4.5 - 8.0 * @sin(phi), gz, 1e-12);
}

test "buildGZArrayM populates the array correctly" {
    const KN = [_]f64{ 0.0, 1.3, 2.6, 3.6, 4.5, 5.0, 5.0, 4.5, 3.5 };
    const angles = [_]f64{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };
    var GZ: [9]f64 = undefined;
    try buildGZArrayM(&KN, &angles, 5.0, &GZ);
    // GZ(0) = 0, GZ(10) = 1.3 - 5 sin 10 = 1.3 - 0.868 = 0.432.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), GZ[0], 1e-12);
    const deg = std.math.pi / 180.0;
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.3 - 5.0 * @sin(10.0 * deg)),
        GZ[1],
        1e-9,
    );
}

test "gzAtAngleM linear interpolation at non-grid angle" {
    const GZ = [_]f64{ 0.0, 0.3, 0.6, 0.9, 1.0, 0.8, 0.4, 0.0, -0.4 };
    const angles = [_]f64{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };
    const gz_15 = try gzAtAngleM(&GZ, &angles, 15.0);
    // (0.3 + 0.6) / 2 = 0.45.
    try std.testing.expectApproxEqAbs(@as(f64, 0.45), gz_15, 1e-12);
}

test "gzAtAngleM clamps at endpoints" {
    const GZ = [_]f64{ 0.0, 0.3, 0.6 };
    const angles = [_]f64{ 0, 10, 20 };
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try gzAtAngleM(&GZ, &angles, -5.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), try gzAtAngleM(&GZ, &angles, 100.0), 1e-12);
}

test "maxGZM finds maximum" {
    const GZ = [_]f64{ 0.0, 0.3, 0.6, 0.9, 1.0, 0.8, 0.4, 0.0, -0.4 };
    const m = try maxGZM(&GZ);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), m, 1e-12);
}

test "angleOfMaxGZDeg returns 40" {
    const GZ = [_]f64{ 0.0, 0.3, 0.6, 0.9, 1.0, 0.8, 0.4, 0.0, -0.4 };
    const angles = [_]f64{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };
    const phi_max = try angleOfMaxGZDeg(&GZ, &angles);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), phi_max, 1e-12);
}

test "rangeOfStabilityDeg via linear zero-crossing" {
    const GZ = [_]f64{ 0.0, 0.3, 0.6, 0.9, 1.0, 0.8, 0.4, 0.0, -0.4 };
    const angles = [_]f64{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };
    const range = try rangeOfStabilityDeg(&GZ, &angles);
    // Zero crossing between GZ(70)=0 and GZ(80)=-0.4: t = 0/0.4 = 0
    // -> phi = 70.
    try std.testing.expectApproxEqAbs(@as(f64, 70.0), range, 1e-9);
}

test "rangeOfStabilityDeg interpolates between sign change" {
    const GZ = [_]f64{ 1.0, 0.5, 0.1, -0.3 };
    const angles = [_]f64{ 0, 10, 20, 30 };
    const range = try rangeOfStabilityDeg(&GZ, &angles);
    // Between 20 deg (0.1) and 30 deg (-0.3): t = 0.1 / 0.4 = 0.25.
    // phi = 20 + 0.25 * 10 = 22.5.
    try std.testing.expectApproxEqAbs(@as(f64, 22.5), range, 1e-9);
}

test "dynamic stability over full 80-deg curve via Simpson" {
    // Symmetric triangular GZ peaking at 40 deg, vanishing at 80.
    const GZ = [_]f64{ 0.0, 0.25, 0.5, 0.75, 1.0, 0.75, 0.5, 0.25, 0.0 };
    const angles = [_]f64{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };
    const E = try dynamicStabilityMRad(&GZ, &angles, 80.0);
    // Triangular area: 0.5 * base * height = 0.5 * 80 deg * 1.0
    //                = 40 deg * pi/180 = 0.6981 m rad.
    try std.testing.expectApproxEqAbs(@as(f64, 0.5 * 80.0 * std.math.pi / 180.0), E, 0.01);
}

test "dynamic stability partial range via trapezoidal" {
    const GZ = [_]f64{ 0.0, 0.5, 1.0 };
    const angles = [_]f64{ 0, 10, 20 };
    const E = try dynamicStabilityMRad(&GZ, &angles, 20.0);
    // Trapezoidal: h = 10 deg = pi/18 rad. Area = (0.5*(0+1) + 0.5) * (10 * pi/180)
    // = 1.0 * 0.1745 = 0.1745. But Simpson with 3 points: (1/3)(0 + 4*0.5 + 1.0) * h = 1 * h = 0.1745.
    try std.testing.expectApproxEqAbs(@as(f64, 10.0 * std.math.pi / 180.0), E, 1e-6);
}

test "dynamic stability scales linearly with peak GZ" {
    const GZ_1 = [_]f64{ 0.0, 0.25, 0.5, 0.75, 1.0, 0.75, 0.5, 0.25, 0.0 };
    const GZ_2 = [_]f64{ 0.0, 0.5, 1.0, 1.5, 2.0, 1.5, 1.0, 0.5, 0.0 };
    const angles = [_]f64{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };
    const E_1 = try dynamicStabilityMRad(&GZ_1, &angles, 80.0);
    const E_2 = try dynamicStabilityMRad(&GZ_2, &angles, 80.0);
    try std.testing.expectApproxEqAbs(2.0 * E_1, E_2, 1e-9);
}

test "input rejection: KG zero" {
    try std.testing.expectError(Error.NonPositiveKG, gzFromKN(4.0, 0.0, 0.5));
}

test "input rejection: negative KN" {
    try std.testing.expectError(Error.NegativeKN, gzFromKN(-0.1, 5.0, 0.3));
}

test "input rejection: unequal array lengths" {
    const GZ = [_]f64{ 0.0, 0.3 };
    const angles = [_]f64{ 0, 10, 20 };
    var out: [2]f64 = undefined;
    try std.testing.expectError(Error.UnequalLength, buildGZArrayM(&GZ, &angles, 5.0, &out));
}
