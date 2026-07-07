// yard-csr-fatigue-zig public API.
//
// sn:    DNV-RP-C203 bilinear S-N curve evaluation.
//        log_10(N) = log_10(a_1) - m_1 log_10(delta_sigma)  if N <= N_q
//        log_10(N) = log_10(a_2) - m_2 log_10(delta_sigma)  if N >  N_q
//        with thickness reduction (t / t_ref)^k for t > t_ref.
//
// miner: Palmgren-Miner linear cumulative damage. D = sum n_i / N_i.
//        Failure when D >= 1.0.

pub const sn = @import("sn.zig");
pub const miner = @import("miner.zig");

test {
    _ = sn;
    _ = miner;
}
