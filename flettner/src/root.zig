// yard-flettner-zig public API.
//
// magnus:  Magnus-effect lift and drag coefficients on a rotating
//          circular cylinder. For a spin ratio
//            SR = V_tip / V_apparent = omega * R / V
//          the high-SR Reid 1924 / Thom 1934 envelope is approximated:
//            C_L ~ min(SR * 0.7, 12.0)    (saturates near SR ~ 17)
//            C_D ~ 0.5 + 0.2 SR^2 / (1 + 0.2 SR^2)
//          Caller can override with measured rotor data.
//
// rotor:   Dimensional thrust + side force on a Flettner rotor at
//          apparent-wind angle theta:
//            L = 0.5 rho V^2 (D h) C_L
//            D = 0.5 rho V^2 (D h) C_D
//          and the decomposition into surge / sway forces relative
//          to the ship body axis.
//
// drive:   Electric drive power required to maintain rotor RPM
//          against air-friction torque:
//            P_drive = T_friction * omega
//          with T_friction = 0.5 rho V^2 (pi D h R) C_f.

pub const magnus = @import("magnus.zig");
pub const rotor = @import("rotor.zig");
pub const drive = @import("drive.zig");

test {
    _ = magnus;
    _ = rotor;
    _ = drive;
}
