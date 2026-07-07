// yard-bow-zig public API.
//
// holtrop:  Holtrop-Mennen 1984 bulbous-bow resistance correction.
//           The bulbous-bow contribution to wave resistance is governed
//           by the coefficient c_3 (transverse area at FP normalised
//           against beam x draft) plus the immersion factor P_B that
//           accounts for the bulb being below the still waterline.
//           The bow-form factor c_4 captures the influence of the bow
//           shape on the wave-resistance prediction.
//
// area:     Bulbous-bow transverse area A_BT, the integrated cross-
//           sectional area of the bulb above the keel, and the
//           geometric P_B factor.
//
// resistance: Closed-form bulb-resistance term R_B per Holtrop-Mennen
//             1984:
//               R_B = 0.11 exp(-3 P_B^(-2)) * Fn_i^3 * A_BT^(1.5) *
//                     rho * g / (1 + Fn_i^2)
//             where Fn_i is the Froude number based on the bulb-tip
//             immersion depth.

pub const holtrop = @import("holtrop.zig");
pub const area = @import("area.zig");
pub const resistance = @import("resistance.zig");

test {
    _ = holtrop;
    _ = area;
    _ = resistance;
}
