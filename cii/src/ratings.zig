//! MEPC.354(78) Annex 2 CII rating boundaries by ship type.

const std = @import("std");
const cii = @import("cii.zig");

pub const ShipType = enum {
    bulk_carrier,
    gas_carrier,
    tanker,
    container,
    general_cargo,
    refrigerated_cargo,
    lng_carrier,
    ro_ro_cargo,
    ro_ro_passenger,
    cruise_passenger,

    pub fn boundaries(self: ShipType) RatingBoundaries {
        return switch (self) {
            .bulk_carrier => .{ .d1 = 0.86, .d2 = 0.94, .d3 = 1.06, .d4 = 1.18 },
            .gas_carrier => .{ .d1 = 0.86, .d2 = 0.91, .d3 = 1.12, .d4 = 1.44 },
            .tanker => .{ .d1 = 0.82, .d2 = 0.93, .d3 = 1.08, .d4 = 1.28 },
            .container => .{ .d1 = 0.83, .d2 = 0.94, .d3 = 1.07, .d4 = 1.19 },
            .general_cargo => .{ .d1 = 0.83, .d2 = 0.94, .d3 = 1.06, .d4 = 1.19 },
            .refrigerated_cargo => .{ .d1 = 0.78, .d2 = 0.91, .d3 = 1.07, .d4 = 1.20 },
            .lng_carrier => .{ .d1 = 0.89, .d2 = 0.98, .d3 = 1.06, .d4 = 1.13 },
            .ro_ro_cargo => .{ .d1 = 0.86, .d2 = 0.94, .d3 = 1.06, .d4 = 1.16 },
            .ro_ro_passenger => .{ .d1 = 0.86, .d2 = 0.94, .d3 = 1.06, .d4 = 1.16 },
            .cruise_passenger => .{ .d1 = 0.87, .d2 = 0.95, .d3 = 1.06, .d4 = 1.16 },
        };
    }
};

pub const RatingBoundaries = struct {
    d1: f64,
    d2: f64,
    d3: f64,
    d4: f64,

    pub fn classify(self: RatingBoundaries, attained: f64, required: f64) cii.Rating {
        const ratio = attained / required;
        if (ratio < self.d1) return .A;
        if (ratio < self.d2) return .B;
        if (ratio < self.d3) return .C;
        if (ratio < self.d4) return .D;
        return .E;
    }
};

pub fn classifyShip(type: ShipType, attained: f64, required: f64) cii.Rating {
    return type.boundaries().classify(attained, required);
}

test "tanker boundaries stricter than bulk at band edges" {
    const b = ShipType.tanker.boundaries();
    try std.testing.expect(b.d1 < 0.86);
    try std.testing.expectEqual(cii.Rating.A, b.classify(0.80, 1.0));
    try std.testing.expectEqual(cii.Rating.E, b.classify(1.30, 1.0));
}

test "container ship rating at ratio 1.0 is C" {
    const b = ShipType.container.boundaries();
    try std.testing.expectEqual(cii.Rating.C, b.classify(1.0, 1.0));
}

test "classifyShip dispatches tanker table" {
    try std.testing.expectEqual(cii.Rating.B, classifyShip(.tanker, 0.90, 1.0));
}