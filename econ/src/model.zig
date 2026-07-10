//! Annual-cashflow ship economics.
//!
//! Conventions: money in a single consistent currency unit ("cu"); the
//! Trials score on relative economics, so the unit cancels. Rates are
//! fractions (0.08 = 8%).

const std = @import("std");

pub const Capex = struct {
    /// Hull + outfit acquisition cost.
    hull_cu: f64,
    /// Propulsion/rig acquisition cost.
    propulsion_cu: f64,

    pub fn total(self: Capex) f64 {
        return self.hull_cu + self.propulsion_cu;
    }
};

pub const Finance = struct {
    /// Cost of capital per year.
    interest_rate: f64,
    /// Economic life [years].
    life_years: u32,
};

/// Capital recovery factor: the fraction of capex charged per year to
/// amortize principal + interest over the economic life.
///   CRF = r (1+r)^n / ((1+r)^n - 1);  CRF -> 1/n as r -> 0.
pub fn capitalRecoveryFactor(f: Finance) f64 {
    const n: f64 = @floatFromInt(f.life_years);
    if (f.interest_rate == 0.0) return 1.0 / n;
    const growth = std.math.pow(f64, 1.0 + f.interest_rate, n);
    return f.interest_rate * growth / (growth - 1.0);
}

pub const Opex = struct {
    /// Crew cost per year.
    crew_cu_per_year: f64,
    /// Maintenance as a fraction of total capex per year.
    maintenance_frac: f64,
    /// Fixed insurance (hull & machinery) as a fraction of capex per year,
    /// before the mission-specific expected-loss premium.
    insurance_frac: f64,
};

pub const VoyageCosts = struct {
    /// Propulsive energy per voyage [kWh] (0 for pure sail).
    energy_kwh: f64,
    /// Energy price [cu/kWh].
    energy_price_cu_per_kwh: f64,
    /// Port dues + handling per voyage.
    port_cu: f64,
};

pub const VoyageProfile = struct {
    /// Sea days per voyage (from the mission Monte Carlo mean).
    voyage_days: f64,
    /// Port turnaround days per voyage.
    turnaround_days: f64,
    /// Probability the vessel is lost per voyage (mission loss rate).
    loss_rate: f64,
    /// Cargo delivered per surviving voyage [t].
    cargo_t: f64,
    /// Freight rate earned [cu/t delivered].
    freight_rate_cu_per_t: f64,
    /// Operating days per year available for trading.
    operating_days_per_year: f64 = 350.0,
};

pub const Annual = struct {
    voyages_per_year: f64,
    cargo_delivered_t: f64,
    revenue_cu: f64,
    capital_charge_cu: f64,
    opex_cu: f64,
    voyage_costs_cu: f64,
    /// Expected-loss premium: loss probability per voyage x voyages x capex.
    expected_loss_cu: f64,
    total_cost_cu: f64,
    profit_cu: f64,
    /// Required Freight Rate: cu per delivered tonne that zeroes profit.
    rfr_cu_per_t: f64,
};

pub fn annual(capex: Capex, fin: Finance, opex: Opex, vc: VoyageCosts, p: VoyageProfile) Annual {
    const cycle_days = p.voyage_days + p.turnaround_days;
    const voyages = p.operating_days_per_year / cycle_days;
    // Lost voyages deliver nothing; expectation over the Monte Carlo rate.
    const delivered = voyages * p.cargo_t * (1.0 - p.loss_rate);

    const revenue = delivered * p.freight_rate_cu_per_t;
    const capital = capex.total() * capitalRecoveryFactor(fin);
    const fixed_opex = opex.crew_cu_per_year + (opex.maintenance_frac + opex.insurance_frac) * capex.total();
    const per_voyage = voyages * (vc.energy_kwh * vc.energy_price_cu_per_kwh + vc.port_cu);
    const expected_loss = voyages * p.loss_rate * capex.total();

    const total = capital + fixed_opex + per_voyage + expected_loss;
    return .{
        .voyages_per_year = voyages,
        .cargo_delivered_t = delivered,
        .revenue_cu = revenue,
        .capital_charge_cu = capital,
        .opex_cu = fixed_opex,
        .voyage_costs_cu = per_voyage,
        .expected_loss_cu = expected_loss,
        .total_cost_cu = total,
        .profit_cu = revenue - total,
        .rfr_cu_per_t = if (delivered > 0) total / delivered else std.math.inf(f64),
    };
}

const test_capex = Capex{ .hull_cu = 8_000_000, .propulsion_cu = 2_000_000 };
const test_fin = Finance{ .interest_rate = 0.08, .life_years = 20 };
const test_opex = Opex{ .crew_cu_per_year = 900_000, .maintenance_frac = 0.02, .insurance_frac = 0.01 };
const test_vc = VoyageCosts{ .energy_kwh = 86_000, .energy_price_cu_per_kwh = 0.12, .port_cu = 15_000 };
const test_profile = VoyageProfile{
    .voyage_days = 1.06,
    .turnaround_days = 1.0,
    .loss_rate = 0.0,
    .cargo_t = 5000,
    .freight_rate_cu_per_t = 4.0,
};

test "capital recovery factor matches hand computation" {
    // 8% over 20 years: 0.08 * 1.08^20 / (1.08^20 - 1) = 0.1018522...
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.10185221),
        capitalRecoveryFactor(test_fin),
        1e-7,
    );
}

test "zero interest amortizes to straight line" {
    const crf = capitalRecoveryFactor(.{ .interest_rate = 0.0, .life_years = 25 });
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 25.0), crf, 1e-15);
}

test "break-even freight rate zeroes profit" {
    const base = annual(test_capex, test_fin, test_opex, test_vc, test_profile);
    var at_rfr = test_profile;
    at_rfr.freight_rate_cu_per_t = base.rfr_cu_per_t;
    const be = annual(test_capex, test_fin, test_opex, test_vc, at_rfr);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), be.profit_cu, 1e-6);
}

test "risk raises the required freight rate" {
    const safe = annual(test_capex, test_fin, test_opex, test_vc, test_profile);
    var risky_profile = test_profile;
    risky_profile.loss_rate = 0.02;
    const risky = annual(test_capex, test_fin, test_opex, test_vc, risky_profile);
    try std.testing.expect(risky.rfr_cu_per_t > safe.rfr_cu_per_t);
    try std.testing.expect(risky.expected_loss_cu > 0);
    try std.testing.expect(risky.cargo_delivered_t < safe.cargo_delivered_t);
}

test "faster turnaround lowers the required freight rate" {
    const slow = annual(test_capex, test_fin, test_opex, test_vc, test_profile);
    var quick_profile = test_profile;
    quick_profile.turnaround_days = 0.5;
    const quick = annual(test_capex, test_fin, test_opex, test_vc, quick_profile);
    try std.testing.expect(quick.voyages_per_year > slow.voyages_per_year);
    try std.testing.expect(quick.rfr_cu_per_t < slow.rfr_cu_per_t);
}

test "pure sail pays no energy bill" {
    var sail_vc = test_vc;
    sail_vc.energy_kwh = 0;
    const sail = annual(test_capex, test_fin, test_opex, sail_vc, test_profile);
    const powered = annual(test_capex, test_fin, test_opex, test_vc, test_profile);
    try std.testing.expect(sail.voyage_costs_cu < powered.voyage_costs_cu);
    try std.testing.expect(sail.rfr_cu_per_t < powered.rfr_cu_per_t);
}
