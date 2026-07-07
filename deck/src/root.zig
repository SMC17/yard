// yard-deck-zig public API.
//
// crane:   Deck-crane SWL (Safe Working Load) and outreach
//          relationship. Crane moment = SWL * outreach. A standard
//          load chart is a piecewise-linear or piecewise-monotone
//          function SWL(r) with SWL decreasing as r increases.
//
// tipping: Crane-on-ship tipping check. The crane heeling moment
//          must remain below the righting moment of the vessel.
//
// dynamic: DNV / IACS dynamic amplification factor (DAF) for the
//          crane-load combined with ship-motion accelerations:
//            SWL_dynamic = SWL * (1 + a_v / g)
//          and the lashing-force / outreach geometry under
//          significant deck acceleration.

pub const crane = @import("crane.zig");
pub const tipping = @import("tipping.zig");
pub const dynamic = @import("dynamic.zig");

test {
    _ = crane;
    _ = tipping;
    _ = dynamic;
}
