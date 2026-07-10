//! yard-era — historical constraint envelopes for the Yard Trials.
//!
//! Materials with design allowables, per-era propulsion menus, historical
//! measurement/treaty rule functions, and an envelope checker. History
//! supplies the box rules; the physics modules stay era-agnostic.
//!
//! Proof level: unit-tested (static reference data + exact rule formulas).

pub const materials = @import("materials.zig");
pub const rules = @import("rules.zig");
pub const envelope = @import("envelope.zig");

test {
    _ = materials;
    _ = rules;
    _ = envelope;
}
