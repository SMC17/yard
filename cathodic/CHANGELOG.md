# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `faraday.F_C_per_mol` Faraday constant.
- `faraday.M_*_kg_per_mol` molar masses for iron, zinc, aluminum,
  magnesium.
- `faraday.n_*` typical valences.
- `faraday.massConsumedKg` and `annualMassPerAmpereKgPerA`.
- `design.currentDemandA`, `requiredNetAnodeMassKg`,
  `requiredGrossAnodeMassKg`.
- `design.AnodeAlloy` enum with electrochemical capacities for
  Al-Zn-In, Zn, Mg.
- 19-test unit suite including Faraday closed-form, kg / A / yr
  references, DNV-RP-B401 worked example (750 A demand, 65 700 kg
  net mass, 82 125 kg gross at 0.8 utilisation), and typed-error
  rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Anode capacity values flagged `claimed` until cross-verified
against supplier datasheets for the specific alloy grade.
