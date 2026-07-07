const std = @import("std");

pub const Error = error{
    NonPositiveArea,
    NonPositiveDensity,
    NonPositiveLife,
    NonPositiveCapacity,
    InvalidUtilisation,
};

/// Total protective current demand:
///   I_total = A_surface * i_mean_current_density
/// where current densities are typically in A/m^2 (DNV-RP-B401
/// recommends ~0.150 A/m^2 mean for bare steel in cold seawater).
pub fn currentDemandA(A_surface_m2: f64, i_mean_a_per_m2: f64) Error!f64 {
    if (!(A_surface_m2 > 0)) return Error.NonPositiveArea;
    if (!(i_mean_a_per_m2 > 0)) return Error.NonPositiveDensity;
    return A_surface_m2 * i_mean_a_per_m2;
}

/// Required net anode mass per DNV-RP-B401 style:
///   m_net = (I_total * design_life_years * 8760 h/yr) / capacity_Ah_per_kg
/// where `capacity_Ah_per_kg` is the anode electrochemical capacity
/// (e.g. ~ 2000 A h / kg for Al-Zn-In; 780 A h / kg for Zn). The
/// utilisation factor scales the net mass to the gross mass: 0.8 for
/// flush-mounted, 0.9 for stand-off / bracelet.
pub fn requiredNetAnodeMassKg(
    I_total_a: f64,
    design_life_yr: f64,
    capacity_ah_per_kg: f64,
) Error!f64 {
    if (!(I_total_a > 0)) return Error.NonPositiveCapacity;
    if (!(design_life_yr > 0)) return Error.NonPositiveLife;
    if (!(capacity_ah_per_kg > 0)) return Error.NonPositiveCapacity;
    return I_total_a * design_life_yr * 8760.0 / capacity_ah_per_kg;
}

/// Required gross anode mass = net mass / utilisation factor.
pub fn requiredGrossAnodeMassKg(net_mass_kg: f64, utilisation: f64) Error!f64 {
    if (!(net_mass_kg > 0)) return Error.NonPositiveCapacity;
    if (!(utilisation > 0.0 and utilisation <= 1.0)) return Error.InvalidUtilisation;
    return net_mass_kg / utilisation;
}

pub const AnodeAlloy = enum {
    /// Aluminum-zinc-indium alloy, typical 2000 Ah/kg.
    Al_Zn_In,
    /// Zinc, typical 780 Ah/kg.
    Zn,
    /// Magnesium, typical 1230 Ah/kg.
    Mg,

    pub fn capacityAhPerKg(self: AnodeAlloy) f64 {
        return switch (self) {
            .Al_Zn_In => 2000.0,
            .Zn => 780.0,
            .Mg => 1230.0,
        };
    }
};

test "current demand: 5000 m^2 at 0.150 A/m^2 = 750 A" {
    const I = try currentDemandA(5000.0, 0.150);
    try std.testing.expectApproxEqAbs(@as(f64, 750.0), I, 1e-9);
}

test "required net anode mass: 750 A * 20 yr * 8760 h / (2000 Ah/kg) = 65700 kg" {
    const m = try requiredNetAnodeMassKg(750.0, 20.0, 2000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 65_700.0), m, 1e-6);
}

test "required gross at 0.8 utilisation increases by 1.25" {
    const m_gross = try requiredGrossAnodeMassKg(65_700.0, 0.8);
    try std.testing.expectApproxEqAbs(@as(f64, 65_700.0 / 0.8), m_gross, 1e-6);
}

test "Al-Zn-In alloy capacity 2000 Ah/kg" {
    try std.testing.expectApproxEqAbs(@as(f64, 2000.0), AnodeAlloy.Al_Zn_In.capacityAhPerKg(), 1e-12);
}

test "Zn alloy capacity 780 Ah/kg" {
    try std.testing.expectApproxEqAbs(@as(f64, 780.0), AnodeAlloy.Zn.capacityAhPerKg(), 1e-12);
}

test "Mg alloy capacity 1230 Ah/kg" {
    try std.testing.expectApproxEqAbs(@as(f64, 1230.0), AnodeAlloy.Mg.capacityAhPerKg(), 1e-12);
}

test "Al-Zn-In requires less mass than Zn for same demand" {
    const m_al = try requiredNetAnodeMassKg(100.0, 10.0, AnodeAlloy.Al_Zn_In.capacityAhPerKg());
    const m_zn = try requiredNetAnodeMassKg(100.0, 10.0, AnodeAlloy.Zn.capacityAhPerKg());
    try std.testing.expect(m_al < m_zn);
}

test "input rejection: zero area" {
    try std.testing.expectError(Error.NonPositiveArea, currentDemandA(0.0, 0.150));
}

test "input rejection: utilisation > 1" {
    try std.testing.expectError(Error.InvalidUtilisation, requiredGrossAnodeMassKg(100.0, 1.1));
}

test "input rejection: zero design life" {
    try std.testing.expectError(Error.NonPositiveLife, requiredNetAnodeMassKg(100.0, 0.0, 2000.0));
}
