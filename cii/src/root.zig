// yard-cii-zig public API.
//
// cii: IMO MEPC.354(78) Carbon Intensity Indicator operational
//      rating. Attained AER (Annual Efficiency Ratio):
//        AER = sum_f (FC_f * C_F_f) / (DWT * D)
//      where FC_f is annual fuel consumption per fuel type, C_F_f
//      is the carbon factor per MEPC.337(76), DWT is the capacity,
//      and D is the annual distance sailed in nm. The required CII
//      is the baseline reference line times the year-specific Z
//      reduction factor (1 - Z%). The rating A..E follows the
//      d1..d4 vector against the required CII.

pub const cii = @import("cii.zig");

test {
    _ = cii;
}
