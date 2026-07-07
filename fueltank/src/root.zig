// yard-fueltank-zig public API.
//
// reg_12a: MARPOL Annex I Regulation 12A oil-fuel-tank protection.
//          For any oil fuel tank with individual capacity > 600 m^3:
//            w >= 0.4 + 2.4 C / 20000 m  (with min 1.0 m, max 2.0 m)
//            h >= max(B / 20, 2.0 m) but not more than 2.0 m
//          where C is the total volume of oil fuel in m^3, w is the
//          side-distance, h is the double-bottom height, and B is the
//          ship's moulded breadth. The regulation applies to ships
//          contracted on or after 1 August 2010 with capacity >= 600
//          m^3 of oil fuel.

pub const reg_12a = @import("reg_12a.zig");

test {
    _ = reg_12a;
}
