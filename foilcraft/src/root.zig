// yard-foilcraft-zig public API.
//
// foil: Hydrofoil lift, takeoff-speed, and cavitation-onset gate.
//       Lift L = 0.5 rho V^2 S C_L. At takeoff V_TO when L = W:
//         V_TO = sqrt(2 W / (rho S C_L)).
//       Cavitation onset when local-suction pressure drops below
//       vapour pressure; a simplified gate flags V > V_cav with
//         V_cav = sqrt((p_0 - p_v) / (0.5 rho * (-C_p_min)))
//       and C_p_min ~ -1.0 for sub-cavitating sections.

pub const foil = @import("foil.zig");

test {
    _ = foil;
}
