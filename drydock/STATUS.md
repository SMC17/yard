# Status

yard-drydock-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `blocks.averagePerBlockN` | `unit-tested` | W / N closed form |
| `blocks.nonUniformReactionsN` | `unit-tested` | constant density gives constant R_i; linear gives linear |
| `blocks.peakReactionN`, `totalReactionN` | `unit-tested` | max / sum closed forms |
| `pressure.allowablePressurePa` | `claimed` | 2 / 5 / 50 / 10 MPa for softwood / hardwood / steel / concrete per Heger Dockmaster + USN MIL-STD-1625D guidance |
| `pressure.bearingPressurePa` | `unit-tested` | R / A; 1 MPa at 500 kN / 0.5 m^2 |
| `pressure.pressureVerdict` | `unit-tested` | <= boundary inclusive |
| `pressure.requiredAreaM2` | `unit-tested` | R / p_allow; soft > hard at same load |
| `transverse.virtualGGRiseM` | `unit-tested` | P KG / Delta closed form; linear / inverse scaling |
| `transverse.residualGMM` | `unit-tested` | initial - GG_v; can go negative |
| `transverse.dockingStabilityVerdict` | `unit-tested` | > 0 pass; 0 or negative fail |
| `transverse.criticalBlockForceN` | `unit-tested` | W - B; clamped to zero |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `38/38 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: allowable-pressure table flagged `claimed`;
  per-block-material certification values must be verified for
  certified docking. Block-plan reactions assume rigid block beams;
  for soft / non-uniform settling the continuous-beam approximation
  must be refined.
- Type-II missed risk guard: typed-error rejection for non-positive
  load / area / weight / block count / Delta / GM, degenerate
  density distribution, zero spacing. Docking-stability verdict
  treats GM = 0 as a fail (Type-II envelope).
- Type-III category guard: drydocking arrangement kernel only;
  not a wood-creep / settling time-history; not a flooding-rate
  sequencer; not a seismic-amplification calculator; not a drydock
  floor structural FE.

## What is not covered (v0.0.0)

- Floating-dock buoyancy / pumping schedule.
- Wood-block creep / settling time-history.
- Drydock flooding rate / valve sequencing.
- 2D / 3D block layout from ship-form vertical curves.
- Seismic / earthquake load amplification.
- Drydock floor / wall structural FE.

## Composition

- Inputs W, Delta, GM, B_residual from `yard-stability-zig` +
  `yard-hydro-zig` at the docking water level.
- Output peak reaction couples to `pressure.bearingPressurePa` to
  size keel-block area; `requiredAreaM2` inversely sizes the
  minimum block area per material.
- Critical block force closes the docking-stability loop into the
  IS Code intact-stability companion in `yard-stability-zig`.
