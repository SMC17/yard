// yard-load-line-zig public API.
//
// freeboard: International Convention on Load Lines (ICLL) 1966/88
//            tabular summer freeboard for Type A and Type B ships,
//            with corrections for block coefficient, depth, sheer,
//            and superstructure. Tabular freeboard for Type A and
//            Type B per Annex I Reg. 28 (Type A) and Reg. 28(2)
//            (Type B).

pub const freeboard = @import("freeboard.zig");

test {
    _ = freeboard;
}
