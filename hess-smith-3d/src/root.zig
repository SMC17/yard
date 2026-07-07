// yard-hess-smith-3d-zig public API.
//
// hess_smith_3d: 3D source-distribution panel method using
//                point-source-at-centroid approximation. Triangular or
//                quadrilateral panels are reduced to a centroid plus
//                outward-normal plus area. Gauss elimination solves the
//                influence matrix. Validation on a sphere uses Cp at
//                the equator expected at -5/4.

pub const hess_smith_3d = @import("hess_smith_3d.zig");
pub const sphere_mesh = @import("sphere_mesh.zig");

test {
    _ = hess_smith_3d;
    _ = sphere_mesh;
}
