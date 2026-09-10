// yard-resistance-zig public API.
//
// Modules:
//   ittc57:  Frictional resistance via the ITTC-57 model-ship correlation
//            line. C_F = 0.075 / (log10(Rn) - 2)^2.
//   holtrop: Holtrop-Mennen 1984 reanalysis form factor (1+k) and wave
//            resistance R_W (low-Fn branch + 0.40<Fn<0.55 blend +
//            c_17/m_3 high-Fn branch).
//   holtrop_extended: Full c_1..c_16, m_1/m_3/m_4, lambda parameter,
//            appendage resistance with HM 1984 Table 5 form factors,
//            roughness allowance C_A (short and full bulb-corrected).

pub const ittc57 = @import("ittc57.zig");
pub const holtrop = @import("holtrop.zig");
pub const holtrop_extended = @import("holtrop_extended.zig");

test {
    _ = ittc57;
    _ = holtrop;
    _ = holtrop_extended;
}
