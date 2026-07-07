// yard-strip-theory-zig public API.
//
// heave: 1-DOF heave equation solver in the frequency domain.
//        (M + A_33(omega)) X_ddot + B_33(omega) X_dot + C_33 X = F_3(omega)
//        Returns the complex response amplitude and the RAO modulus.

pub const heave = @import("heave.zig");

test {
    _ = heave;
}
