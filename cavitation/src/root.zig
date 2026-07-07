// yard-cavitation-zig public API.
//
// burrill: Burrill cavitation chart predictor. The Burrill thrust-
//          loading coefficient tau_c = T / (0.5 rho V_R^2 A_P) is
//          plotted against the local cavitation number
//          sigma_n = (p_0 - p_v) / (0.5 rho V_R^2) with V_R the
//          velocity at 0.7 R: V_R^2 = V_a^2 + (0.7 pi n D)^2.
//
// keller:  Keller minimum projected blade-area ratio criterion for
//          merchant-ship propellers: A_E / A_0 >= (1.3 + 0.3 Z) T /
//          ((p_0 - p_v) D^2) + k.

pub const burrill = @import("burrill.zig");
pub const keller = @import("keller.zig");

test {
    _ = burrill;
    _ = keller;
}
