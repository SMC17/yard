// yard-roro-zig public API.
//
// deck_load: RoRo / ferry vehicle-deck inertial loading. The total
//            apparent weight of a vehicle on a moving deck is
//              W_apparent = m (g + a_v)
//            where a_v is the vertical acceleration at the deck level
//            from ship-motion response. Lashing systems are designed
//            against this apparent weight plus a horizontal load
//              F_h = m (a_h + g tan phi)
//            where a_h is the lateral acceleration and phi is the
//            instantaneous roll angle.

pub const deck_load = @import("deck_load.zig");

test {
    _ = deck_load;
}
