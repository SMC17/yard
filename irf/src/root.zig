// yard-irf-zig public API.
//
// cummins: Cummins 1962 / Ogilvie 1964 time-domain motion equation
//          for a single DOF:
//            [M + A_inf] ddot{x} + integral_0^t K(t - tau) dot{x}(tau) dtau
//             + C x = F(t)
//          The retardation (impulse-response) function K(t) is the
//          inverse cosine transform of the frequency-dependent damping
//          coefficient B(omega):
//            K(t) = (2 / pi) integral_0^inf B(omega) cos(omega t) domega
//          The infinite-frequency added mass A_inf can be recovered
//          from the frequency-dependent added mass A(omega) at a
//          reference frequency:
//            A_inf = A(omega_ref) + (1 / omega_ref) integral_0^inf
//                    K(t) sin(omega_ref t) dt.

pub const cummins = @import("cummins.zig");

test {
    _ = cummins;
}
