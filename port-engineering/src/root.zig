// yard-port-engineering-zig public API.
//
// breakwater: Wave transmission coefficient K_t past a rubble-mound
//             breakwater; armour-stone size via Hudson formula;
//             wave run-up.
//
// channel:    Approach-channel design: gross depth = T + UKC +
//             squat + heave + safety; PIANC width.
//
// basin:      Harbour basin resonance: Helmholtz natural period
//             T_H = 2 pi sqrt(A_basin L_channel / (g A_channel)) and
//             standing-wave seiche periods.

pub const breakwater = @import("breakwater.zig");
pub const channel = @import("channel.zig");
pub const basin = @import("basin.zig");

test {
    _ = breakwater;
    _ = channel;
    _ = basin;
}
