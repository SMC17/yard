// yard-collision-zig public API.
//
// minorsky:  Minorsky 1959 right-angle ship-ship collision energy
//            absorption: E_abs = 47.1 R_T + 32.7 (MN m) where R_T is
//            the resistance-factor (1 ft^3 * 1 ft thick) of damaged
//            steel volume. SI converted equivalent:
//            E_abs [MJ] = 47.1 R_T + 32.7 with R_T = sum t_i V_i
//            in m^3 (with t in m, V in m^2 * m).
//
// kinetic:   Kinetic energy of a moving mass with hydrodynamic added
//            mass correction (Minorsky used 1.4 for the struck vessel
//            and 1.0 for the striking vessel).

pub const minorsky = @import("minorsky.zig");
pub const kinetic = @import("kinetic.zig");

test {
    _ = minorsky;
    _ = kinetic;
}
