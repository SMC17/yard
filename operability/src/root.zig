//! yard-operability — seakeeping operability: the ship's flight envelope.
//!
//! NORDFORSK 1987 / STANAG 4154-style limiting criteria, Rayleigh-
//! exceedance event statistics (Ochi slamming, deck wetness, propeller
//! emergence), and O'Hanlon-McCauley motion sickness incidence. Consumes
//! RMS values and spectral variances from the rao-spectrum / seakeeping
//! chain; produces pass/fail envelopes and event rates.
//!
//! Proof level: unit-tested (published criteria tables + closed-form
//! narrow-band statistics, hand-checked).

pub const criteria = @import("criteria.zig");
pub const events = @import("events.zig");
pub const msi = @import("msi.zig");

test {
    _ = criteria;
    _ = events;
    _ = msi;
}
