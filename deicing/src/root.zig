// yard-deicing-zig public API.
//
// overland: Overland 1986 icing predictor index for marine
//           superstructure icing. The dimensionless icing predictor
//           is:
//             PR = V_wind * (T_freeze - T_air) / (1 + 0.4 (T_sea - T_freeze))
//           where T_freeze = -1.7 deg C is the salt-water freezing
//           point. The empirical accretion-rate category map:
//             PR <= 0          : none
//             0 < PR <= 22.4   : light
//             22.4 < PR <= 53.3: moderate
//             53.3 < PR <= 83.0: heavy
//             PR > 83.0        : extreme
//
// accreted: Accreted ice weight on a topside surface:
//             W = rho_ice * h_ice * A_surface
//           with rho_ice ~ 900 kg/m^3 and h_ice the accretion
//           thickness derived from the icing class * exposure duration.

pub const overland = @import("overland.zig");
pub const accreted = @import("accreted.zig");

test {
    _ = overland;
    _ = accreted;
}
