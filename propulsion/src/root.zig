// yard-propulsion-zig public API.
//
// wageningen: Wageningen B-series propeller K_T and K_Q polynomial
//             evaluator. Coefficient tables from Oosterveld and van
//             Oossanen 1975.
// openwater: Open-water efficiency, three-point quadratic K_T/K_Q
//             fit, ITTC-78 Lerbs Reynolds correction, Holtrop-Mennen
//             eta_R single-screw and twin-screw, peak-efficiency J
//             brute-force search.

pub const wageningen = @import("wageningen.zig");
pub const openwater = @import("openwater.zig");

test {
    _ = wageningen;
    _ = openwater;
}
