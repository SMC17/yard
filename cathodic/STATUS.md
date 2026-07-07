# Status

yard-cathodic-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `faraday.F_C_per_mol` | `known-constant` | NIST CODATA 2019 exact value 96485.33212 C/mol |
| `faraday.massConsumedKg` | `unit-tested` | I=1 A, t=1 hr -> M / (n F) * 3600 closed form |
| `faraday.annualMassPerAmpereKgPerA` | `unit-tested` | iron 9.13, aluminum 2.94, zinc 10.69 kg/A/yr |
| `design.currentDemandA` | `unit-tested` | 5000 m^2 * 0.150 = 750 A |
| `design.requiredNetAnodeMassKg` | `unit-tested` | I*L*8760 / capacity = 65700 kg |
| `design.requiredGrossAnodeMassKg` | `unit-tested` | gross = net / utilisation |
| `design.AnodeAlloy.capacityAhPerKg` | `claimed` | typical values 2000 / 780 / 1230 A h / kg; alloy-grade and supplier-specific values can vary |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `19/19 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: alloy electrochemical capacity values
  flagged `claimed`; the typical values 2000 / 780 / 1230 A h / kg
  are widely cited but supplier-specific testing may give a value
  within +/- 10 %. Faraday-law evaluation is `unit-tested`.
- Type-II missed risk guard: typed-error rejection for zero current,
  time, area, life, capacity, and utilisation outside (0, 1].
- Type-III category guard: sizing kernel only; not a potential-
  distribution FE solver; not a coating-degradation predictor;
  not an anode-bracket structural verifier; not an ICCP-supply
  sizer.

## What is not covered (v0.0.0)

- Coating-degradation time-history.
- Anode-resistance Dwight formula.
- Potential-distribution FE solve.
- Environmental corrections (mud, seabed, hot, brackish).
- Impressed-current power-supply sizing.
- Anode-bracket structural verification.

## Composition

- Current demand inputs A_surface from `yard-hydro-zig` wetted-
  surface output.
- Anode mass composes externally with classification-society
  procedures for fastening and distribution.
