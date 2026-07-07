// yard-bem-zig public API.
//
// hess_smith_2d: 2D Hess-Smith non-lifting source-distribution panel
//                method. Builds the influence-coefficient matrix and
//                solves for source strengths via Gauss elimination.
//                Recovers tangential velocity and pressure coefficient
//                at panel centroids.

pub const hess_smith_2d = @import("hess_smith_2d.zig");

test {
    _ = hess_smith_2d;
}
