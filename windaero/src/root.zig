// yard-windaero-zig public API.
//
// blendermann: Blendermann 1996 wind force / yaw moment coefficients
//              for ships above the waterline. For an apparent wind
//              angle eps measured from the bow (eps = 0 head-wind,
//              pi beam-wind, +/- pi following), the coefficients are
//              approximated by Fourier-style trigonometric expansions
//              calibrated against wind-tunnel data for the major
//              ship-type categories.
//
//              Forces:
//                X = 0.5 rho_air V^2 A_L C_X(eps)
//                Y = 0.5 rho_air V^2 A_T C_Y(eps)
//                N = 0.5 rho_air V^2 A_L L_OA C_N(eps)
//              where A_L is the longitudinal projected area, A_T the
//              transverse projected area, and L_OA the overall length.

pub const blendermann = @import("blendermann.zig");

test {
    _ = blendermann;
}
