// Lat-lon sphere discretization into quadrilateral panels.
//
// Generates N_lat x N_lon panels, each represented as a Panel struct
// with centroid, outward normal, and area for the centroid-source
// approximation in hess_smith_3d.

const std = @import("std");
const hs = @import("hess_smith_3d.zig");

/// Generate panels on a unit sphere centered at the origin. The mesh
/// uses lat-lon grid with `n_lat` latitudinal subdivisions and
/// `n_lon` longitudinal subdivisions. Panels close to the poles are
/// triangular in shape but treated as quadrilaterals with two
/// near-coincident vertices, which the centroid-source approximation
/// handles correctly.
pub fn unitSphere(n_lat: usize, n_lon: usize, out: []hs.Panel) usize {
    std.debug.assert(out.len >= n_lat * n_lon);
    var idx: usize = 0;
    var i: usize = 0;
    while (i < n_lat) : (i += 1) {
        const theta1 = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n_lat));
        const theta2 = std.math.pi * @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(n_lat));
        const theta_c = 0.5 * (theta1 + theta2);
        var j: usize = 0;
        while (j < n_lon) : (j += 1) {
            const phi1 = 2.0 * std.math.pi * @as(f64, @floatFromInt(j)) / @as(f64, @floatFromInt(n_lon));
            const phi2 = 2.0 * std.math.pi * @as(f64, @floatFromInt(j + 1)) / @as(f64, @floatFromInt(n_lon));
            const phi_c = 0.5 * (phi1 + phi2);

            const xc = @sin(theta_c) * @cos(phi_c);
            const yc = @sin(theta_c) * @sin(phi_c);
            const zc = @cos(theta_c);

            // Outward normal on a unit sphere equals the centroid vector.
            const nx = xc;
            const ny = yc;
            const nz = zc;

            // Area of a spherical-rectangle patch is
            //   (phi2 - phi1) * (cos theta1 - cos theta2)
            // For panels of small dtheta the planar-quad approximation
            // gives nearly the same value.
            const area = (phi2 - phi1) * (@cos(theta1) - @cos(theta2));

            out[idx] = .{ .xc = xc, .yc = yc, .zc = zc, .nx = nx, .ny = ny, .nz = nz, .area = area };
            idx += 1;
        }
    }
    return idx;
}

test "unitSphere produces n_lat * n_lon panels" {
    var panels: [96]hs.Panel = undefined;
    const n = unitSphere(8, 12, &panels);
    try std.testing.expectEqual(@as(usize, 96), n);
}

test "unitSphere total area approximates 4 pi" {
    var panels: [200]hs.Panel = undefined;
    const n = unitSphere(10, 20, &panels);
    var total: f64 = 0.0;
    var k: usize = 0;
    while (k < n) : (k += 1) total += panels[k].area;
    try std.testing.expectApproxEqRel(4.0 * std.math.pi, total, 1e-12);
}

test "unitSphere panel centroids lie on the unit sphere" {
    var panels: [96]hs.Panel = undefined;
    _ = unitSphere(8, 12, &panels);
    for (panels) |p| {
        const r_sq = p.xc * p.xc + p.yc * p.yc + p.zc * p.zc;
        try std.testing.expectApproxEqRel(@as(f64, 1.0), r_sq, 1e-12);
    }
}
