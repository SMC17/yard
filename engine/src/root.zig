// yard-engine-zig public API.
//
// sfoc:  Specific fuel-oil consumption curve fit and lookup. Marine
//        engine SFOC vs % MCR is typically published at three points
//        (50, 75, 100 % MCR). A parabolic fit captures the
//        characteristic minimum near 70-80 % MCR.
//
// nox:   IMO MARPOL Annex VI Tier I / II / III NOx weighted-cycle
//        limits as a function of rated engine speed n. Caller compares
//        certified test-cycle weighted NOx emissions against the
//        applicable tier ceiling.

pub const sfoc = @import("sfoc.zig");
pub const nox = @import("nox.zig");

test {
    _ = sfoc;
    _ = nox;
}
