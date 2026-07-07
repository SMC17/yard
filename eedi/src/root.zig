// yard-eedi-zig public API.
//
// eedi: IMO MEPC.308(73) Energy Efficiency Design Index attained-value
//       computation in the simplified main-engine + auxiliary-engine
//       form:
//         EEDI = (Sum P_ME C_F_ME SFC_ME + P_AE C_F_AE SFC_AE) /
//                (Capacity * V_ref * f_i)
//       with carbon-conversion factors C_F per fuel type and per
//       MEPC.337(76). Reduction-factor table per MEPC.328(76) Phase
//       0/1/2/3.

pub const eedi = @import("eedi.zig");

test {
    _ = eedi;
}
