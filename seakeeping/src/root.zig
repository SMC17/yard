// yard-seakeeping-zig public API.
//
// spectra: Wave power-spectral-density functions:
//          Pierson-Moskowitz (fully-developed wind sea),
//          JONSWAP (fetch-limited / developing sea),
//          ITTC modified PM parametrized by (H_s, T_z).
// moments: Spectral moment integration m_n = integral omega^n S(omega) domega
//          via composite Simpson 1/3. Derived statistics H_s and T_z.

pub const spectra = @import("spectra.zig");
pub const moments = @import("moments.zig");

test {
    _ = spectra;
    _ = moments;
}
