// Standard benchmark hull fixtures.
//
// References:
//   Wigley     — Journee 1992; Kajitani-Miyata 1983 cooperative experiment.
//   KCS        — SIMMAN 2002 / KRISO Container Ship (Lloyd et al.).
//   KVLCC2     — MOERI tanker, Tokyo 2005 CFD workshop.
//   Series 60  — Taylor model basin, Cb = 0.60 (Holtrop envelope).

const resistance = @import("yard_resistance");

pub const Id = enum {
    wigley,
    kcs,
    kvlcc2,
    series60_cb60,
};

pub const Fixture = struct {
    id: Id,
    name: []const u8,
    L: f64,
    B: f64,
    T: f64,
    C_B: f64,
    C_P: f64,
    C_M: f64,
    C_WP: f64,
    lcb_pct: f64,
    c_stern: f64,
    displacement_vol: f64,
    wetted_surface: f64,
    /// Design / validation speed [m/s].
    service_speed: f64,
    /// Towing-tank model length [m] for similarity checks (0 = derive from λ=0.05).
    model_length: f64 = 0.0,

    pub fn holtropParticulars(self: Fixture) resistance.holtrop.HullParticulars {
        return .{
            .L = self.L,
            .B = self.B,
            .T = self.T,
            .displacement_vol = self.displacement_vol,
            .S = self.wetted_surface,
            .C_B = self.C_B,
            .C_M = self.C_M,
            .C_P = self.C_P,
            .C_WP = self.C_WP,
            .lcb_pct = self.lcb_pct,
            .c_stern = self.c_stern,
        };
    }

    pub fn modelLength(self: Fixture) f64 {
        if (self.model_length > 0.0) return self.model_length;
        return self.L * 0.05;
    }
};

pub fn get(id: Id) Fixture {
    return switch (id) {
        .wigley => .{
            .id = .wigley,
            .name = "Wigley parabolic",
            .L = 100.0,
            .B = 10.0,
            .T = 6.25,
            .C_B = 4.0 / 9.0,
            .C_P = 2.0 / 3.0,
            .C_M = 2.0 / 3.0,
            .C_WP = 2.0 / 3.0,
            .lcb_pct = 0.0,
            .c_stern = 0.0,
            .displacement_vol = (4.0 / 9.0) * 100.0 * 10.0 * 6.25,
            .wetted_surface = 2.6 * @sqrt((4.0 / 9.0) * 100.0 * 10.0 * 6.25) * 100.0,
            .service_speed = 8.0,
            .model_length = 5.0,
        },
        .kcs => .{
            .id = .kcs,
            .name = "KCS (KRISO Container Ship)",
            .L = 230.7,
            .B = 32.2,
            .T = 10.8,
            .C_B = 0.6505,
            .C_P = 0.662,
            .C_M = 0.982,
            .C_WP = 0.783,
            .lcb_pct = -1.2,
            .c_stern = 0.0,
            .displacement_vol = 52030.0,
            .wetted_surface = 8100.0,
            .service_speed = 12.34,
            .model_length = 11.5,
        },
        .kvlcc2 => .{
            .id = .kvlcc2,
            .name = "KVLCC2 MOERI tanker",
            .L = 320.0,
            .B = 58.0,
            .T = 20.8,
            .C_B = 0.8098,
            .C_P = 0.784,
            .C_M = 0.992,
            .C_WP = 0.872,
            .lcb_pct = 0.0,
            .c_stern = 0.0,
            .displacement_vol = 312622.0,
            .wetted_surface = 27100.0,
            .service_speed = 15.5,
            .model_length = 16.0,
        },
        .series60_cb60 => .{
            .id = .series60_cb60,
            .name = "Series 60 Cb=0.60",
            .L = 120.0,
            .B = 16.4,
            .T = 6.7,
            .C_B = 0.60,
            .C_P = 0.66,
            .C_M = 0.98,
            .C_WP = 0.75,
            .lcb_pct = 0.0,
            .c_stern = 0.0,
            .displacement_vol = 7920.0,
            .wetted_surface = 2800.0,
            .service_speed = 8.5,
            .model_length = 6.0,
        },
    };
}

pub const all: [4]Id = .{ .wigley, .kcs, .kvlcc2, .series60_cb60 };