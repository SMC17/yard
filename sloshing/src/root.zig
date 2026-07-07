// yard-sloshing-zig public API.
//
// rectangular: Linear potential-flow sloshing in a rectangular tank
//              per Faltinsen & Timokha. Natural modes of the free
//              surface satisfy
//                omega_n^2 = g k_n tanh(k_n h)
//              with k_n = (2n + 1) pi / L for antisymmetric modes
//              (the modes excited by horizontal sway). The lowest
//              mode (n = 0) is the dominant resonance.

pub const rectangular = @import("rectangular.zig");

test {
    _ = rectangular;
}
