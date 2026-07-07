// yard-csr-buckling-zig public API.
//
// plate:  Plate elastic critical stress per classical thin-plate theory
//         used by IACS CSR Section 8 and DNV-RP-C201:
//         sigma_cr = k pi^2 E / (12 (1 - nu^2)) (t/b)^2.
//         k depends on aspect ratio and boundary type.
//
// column: Euler critical buckling load and stress for a slender column
//         with effective length factor mu:
//         P_cr = pi^2 E I / (mu L)^2, sigma_cr = P_cr / A.
//
// johnson: Johnson-parabola reduction for short columns where the
//          Euler stress exceeds half the yield stress per CSR Section
//          8.2.2.

pub const plate = @import("plate.zig");
pub const column = @import("column.zig");

test {
    _ = plate;
    _ = column;
}
