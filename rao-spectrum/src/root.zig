// yard-rao-spectrum-zig public API.
//
// spectrum: RAO x wave-spectrum convolution. Given |H(omega)|^2 sampled
//           at ordinates omega_i and a wave spectrum S(omega) at the
//           same ordinates, integrates the response spectrum
//           S_R(omega) = |H(omega)|^2 S(omega) via Simpson 1/3 to
//           recover the n-th spectral moment m_n. Significant response
//           amplitude follows the Rayleigh narrow-band formula
//           sigma_R = sqrt(m_0), H_s_R = 4 sqrt(m_0).

pub const spectrum = @import("spectrum.zig");

test {
    _ = spectrum;
}
