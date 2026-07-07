# yard-engine-zig

Proof level: `unit-tested`

yard-engine-zig is a Zig 0.16 marine-engine kernel covering specific
fuel-oil consumption (SFOC) three-point quadratic curve fit and IMO
MARPOL Annex VI Tier I / II / III weighted NOx emission limits as a
function of rated engine speed.

## What it does

### SFOC

- `sfoc.fitThreePoint(y_50, y_75, y_100)` returns the three quadratic
  coefficients `(a, b, c)` such that `SFOC(x) = a + b x + c x^2`
  matching the input SFOC values at 50, 75, 100 % MCR exactly.
- `sfoc.evaluateSfoc(coeffs, x)` evaluates the SFOC quadratic at any
  load fraction `x` in [0, 110] % MCR.
- `sfoc.engineLoadKw(x_pct, P_MCR)` returns the engine load in kW.
- `sfoc.fuelMassFlowKgPerHr(SFOC, P)` returns the fuel mass flow.

### NOx tiers

- `nox.NoxTier` enum (`Tier_I`, `Tier_II`, `Tier_III`).
- `nox.weightedLimitGPerKwh(tier, n_rpm)` returns the weighted-cycle
  NOx limit in g / kWh per MARPOL Annex VI Regulation 13. The
  rpm-dependent envelope has a low-speed plateau below 130 rpm, a
  power-law middle band, and a high-speed plateau above 2000 rpm.
- `nox.verdict(emission, limit)` returns pass / fail.

## What it is not (v0.0.0)

- No multi-point (more than 3) SFOC interpolation or regression.
- No part-load efficiency-island map.
- No transient turbocharger lag / Hammer effect.
- No certified test-cycle (E2 / E3 / D2) weighting calculator.
- No specific-CO2 from SFOC + C_F crosswalk (compose with
  `yard-eedi-zig` for that).
- No SOx limit (MARPOL Annex VI Reg. 14 deferred).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 19/19 tests passed`.

## Public API

```zig
const yard = @import("yard_engine");

const c = try yard.sfoc.fitThreePoint(180.0, 170.0, 180.0);
const v75 = try yard.sfoc.evaluateSfoc(c, 75.0);
const P = try yard.sfoc.engineLoadKw(75.0, 20_000.0);
const mdot = try yard.sfoc.fuelMassFlowKgPerHr(v75, P);

const limit = try yard.nox.weightedLimitGPerKwh(.Tier_III, 720.0);
const v = yard.nox.verdict(2.0, limit);
```

## Validation

- Three-point quadratic exactly matches the three SFOC inputs.
- A symmetric parabola `y_50 = y_100 = 180`, `y_75 = 170` produces
  a minimum at x = 75.
- A linear case `(180, 178, 176)` returns `c = 0` to 1e-12.
- Engine load 75 % of 20 000 kW gives 15 000 kW.
- Fuel mass flow at 170 g / kWh and 15 MW equals 2550 kg/h.
- Tier I limit at n = 100 rpm equals 17.0 g/kWh (low-speed plateau).
- Tier I limit at n = 2500 rpm equals 9.8 g/kWh (high-speed plateau).
- Tier I limit at n = 720 rpm matches `45 n^(-0.2)` closed form.
- Tier II limit below Tier I at 720 rpm; Tier III below Tier II.
- Tier III limit at n = 720 rpm matches `9 n^(-0.2)`.
- Verdict pass at emission <= limit (inclusive); fail otherwise.
- Typed-error rejection for load outside [0, 110], non-positive
  SFOC, non-positive engine speed, zero MCR.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO MARPOL Annex VI Regulation 13 (NOx Emissions Limits).
- IMO Resolution MEPC.176(58). *Revised MARPOL Annex VI*.
- MAN Energy Solutions. *Project Guides for two-stroke and four-
  stroke marine engines*.
- ISO 8178. *Reciprocating internal combustion engines: Exhaust
  emission measurement*.

## License

AGPL-3.0-or-later.
