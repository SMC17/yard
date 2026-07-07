# Status

yard-saildrone-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `stability.gzWallSidedM` | `unit-tested` | (GM + 0.5 BM_T tan^2 phi) sin phi closed form; small-angle GM sin phi limit |
| `stability.phiMaxGZRad{InRange}` | `unit-tested` | search within deck-edge band; 30-deg ceiling default |
| `stability.maxGZM` | `unit-tested` | returns GZ at peak phi |
| `stability.imoUsvDraftVerdict` | `claimed` | GM >= 0.15 m AND GZ_max >= 0.20 m draft IMO USV Code thresholds |
| `beaufort.beaufortWindSpeed` | `claimed` | WMO 1946 midpoint values for scales 0..12 |
| `beaufort.heelingMomentNm` | `unit-tested` | 0.5 rho v^2 A C_L h closed form; V^2 scaling; linear in A and h |
| `beaufort.heelingMomentFromBeaufortNm` | `unit-tested` | composer; Beaufort-8/4 ratio bound |
| `energy.solarPowerW` | `unit-tested` | A I eta closed form; linear scaling |
| `energy.dailyEnergyWh`, `batteryAutonomyDays`, `netDailyEnergyWh` | `unit-tested` | 24-hour multiplication; C/L autonomy; net = production - load |
| `energy.I_avg_*` | `claimed` | regional insolation midpoints; ordering monotone |
| `energy.eta_pv_si_default` | `claimed` | 22 % monocrystalline-silicon typical |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `36/36 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: wall-sided GZ approximation only;
  diverges at large heel. The 30-deg ceiling in `phiMaxGZRad`
  prevents the spurious large-angle peak. IMO USV Code thresholds
  flagged `claimed` (draft document; ratify when published).
- Type-II missed risk guard: typed-error rejection for non-positive
  GM / BM_T / area / capacity / load, eta > 1, Beaufort > 12, phi
  >= pi/2.
- Type-III category guard: USV stability + Beaufort wind heel +
  energy budget only; not a control / autopilot kernel; not a
  routing optimiser; not a SATCOM / data-link bandwidth analyser;
  not a payload power profiler.

## What is not covered (v0.0.0)

- Full nonlinear GZ integration.
- Sea-state seakeeping response.
- Control / autopilot loop.
- Routing optimisation.
- Data-link budget.
- Payload power profile.

## Composition

- `gzWallSidedM` couples to `yard-stability-zig` for proper
  hydrostatic GZ if the wall-sided approximation breaks down.
- `beaufort.heelingMomentFromBeaufortNm` against the righting
  moment from `gzWallSidedM` closes the wind-heel envelope.
- `solarPowerW` integrates with `dailyEnergyWh` and an external
  on-board load model to size the battery.
