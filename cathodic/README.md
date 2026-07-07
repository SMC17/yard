# yard-cathodic-zig

Proof level: `unit-tested`

yard-cathodic-zig is a Zig 0.16 cathodic-protection kernel covering
Faraday-law mass consumption and DNV-RP-B401-style sacrificial-anode
sizing for current demand, net mass, and gross mass under a
utilisation factor.

## What it does

### Faraday law

- `faraday.F_C_per_mol = 96 485` Faraday constant.
- `faraday.M_iron_kg_per_mol`, `M_zinc_kg_per_mol`,
  `M_aluminum_kg_per_mol`, `M_magnesium_kg_per_mol`.
- `faraday.n_iron`, `n_zinc`, `n_aluminum`, `n_magnesium` typical
  oxidation-reaction valences.
- `faraday.massConsumedKg(I, t, M, n)` evaluates the Faraday law
  `m = I t M / (n F)`.
- `faraday.annualMassPerAmpereKgPerA(M, n)` annualised consumption.

### Anode design

- `design.currentDemandA(A_surface, i_mean)` returns total protective
  current required.
- `design.requiredNetAnodeMassKg(I, life, capacity)` net mass per
  electrochemical capacity (A h / kg).
- `design.requiredGrossAnodeMassKg(net, utilisation)` gross mass
  divided by utilisation (typ. 0.8 flush-mount, 0.9 stand-off).
- `design.AnodeAlloy` enum (`Al_Zn_In`, `Zn`, `Mg`) with
  `capacityAhPerKg()` returning 2000 / 780 / 1230 A h / kg.

## What it is not (v0.0.0)

- No coating-degradation-with-time current-density curve (caller
  supplies a mean value).
- No anode-resistance Dwight formula (Lambert / Cathodic / Pearson
  forms deferred).
- No potential-distribution finite-element solve.
- No environmental-correction tables (mud, seabed, hot, brackish).
- No impressed-current power-supply sizing (caller does this).
- No anode-bracket / attachment structural verification.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 19/19 tests passed`.

## Public API

```zig
const yard = @import("yard_cathodic");

// Iron mass consumed by 1 A for one year.
const m_year = try yard.faraday.annualMassPerAmpereKgPerA(
    yard.faraday.M_iron_kg_per_mol, yard.faraday.n_iron);
// ~ 9.13 kg.

// Anode sizing for 5000 m^2 hull, 0.150 A/m^2 mean current density,
// 20-year design life, Al-Zn-In alloy, 0.8 utilisation.
const I = try yard.cathodic.design.currentDemandA(5000.0, 0.150);
const cap = yard.cathodic.design.AnodeAlloy.Al_Zn_In.capacityAhPerKg();
const m_net = try yard.cathodic.design.requiredNetAnodeMassKg(I, 20.0, cap);
const m_gross = try yard.cathodic.design.requiredGrossAnodeMassKg(m_net, 0.8);
```

## Validation

- Faraday law at 1 A for 1 hour reproduces `M / (n F) * 3600` to
  1e-12.
- Annual mass for iron at 1 A is approximately 9.13 kg / A / yr;
  for aluminum 2.94 kg / A / yr; for zinc 10.69 kg / A / yr.
- Doubling current doubles mass.
- Current demand at 5000 m^2 and 0.150 A/m^2 is 750 A.
- Required net mass for I = 750 A over 20 yr at 2000 A h / kg is
  65 700 kg.
- Required gross at 0.8 utilisation increases by 1 / 0.8 = 1.25.
- Al-Zn-In requires less mass than Zn for the same demand at the
  same life.
- Anode alloy capacities Al-Zn-In 2000, Zn 780, Mg 1230 A h / kg.
- Typed-error rejection for zero current / time / area / capacity /
  design life and utilisation outside (0, 1].

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- DNV-RP-B401. *Cathodic Protection Design*.
- NACE SP0176. *Corrosion Control of Submerged Areas of Permanently
  Installed Steel Offshore Structures Associated with Petroleum
  Production*.
- Roberge, P. R. (2008). *Corrosion Engineering: Principles and
  Practice*. McGraw-Hill.
- Faraday, M. (1834). *Experimental Researches in Electricity*.
  Philosophical Transactions.

## License

Apache-2.0.
