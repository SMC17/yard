// yard-recycling-zig public API.
//
// hkc:    Hong Kong Convention 2009 + EU Ship Recycling Regulation
//         (SRR 1257/2013) compliance. Per-vessel inventory of
//         hazardous materials (IHM) bookkeeping; recycling-facility
//         capacity matching.
//
// ihm:    Inventory of Hazardous Materials. Per-material mass
//         tracking against the HKC Appendix 1 / 2 / 3 hazardous-
//         substance limits and Annex II SRR additions.
//
// recovery: Material recovery yield. For a vessel of LDT given the
//           per-category recovery fraction the recovered tonnages
//           per material category are summed for valorisation.

pub const hkc = @import("hkc.zig");
pub const ihm = @import("ihm.zig");
pub const recovery = @import("recovery.zig");

test {
    _ = hkc;
    _ = ihm;
    _ = recovery;
}
