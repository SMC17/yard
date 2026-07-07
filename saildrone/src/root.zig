// yard-saildrone-zig public API.
//
// stability: USV small-vessel intact stability. For an unmanned
//            wind-powered surface vehicle of length 3-7 m, GZ wall-
//            sided approximation gives:
//              GZ(phi) = (GM + 0.5 BM_T tan^2 phi) sin phi
//            The IMO USV Code (under development) typically requires
//            GZ_max >= 0.20 m at phi >= 25 deg, GM >= 0.15 m.
//
// beaufort:  Beaufort wind-scale heel. Apparent wind speed v_wind
//            against sail area A_s with C_L = 1.2 (close-hauled
//            sail trim) produces heeling moment
//              M_h = 0.5 rho_air v_wind^2 A_s C_L h_sail
//            with h_sail the sail-CG height above the waterline.
//
// energy:    On-board energy budget. Solar panel area A_solar
//            yields P_avg = A_solar * I_avg * eta_pv with I_avg the
//            average insolation [W/m^2] (typ. 200 W/m^2 for North
//            Atlantic, 280 W/m^2 for Mediterranean).

pub const stability = @import("stability.zig");
pub const beaufort = @import("beaufort.zig");
pub const energy = @import("energy.zig");

test {
    _ = stability;
    _ = beaufort;
    _ = energy;
}
