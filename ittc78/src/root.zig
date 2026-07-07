// yard-ittc78-zig public API.
//
// chain: ITTC-78 11-step powering extrapolation. Takes model-scale
//        towing-tank result plus ship-scale geometry and propulsion
//        factors; returns ship-scale effective and delivered power.

pub const chain = @import("chain.zig");

test {
    _ = chain;
}
