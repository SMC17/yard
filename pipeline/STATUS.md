# Status

yard-pipeline-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `stability.dragForcePerLengthNM` | `unit-tested` | 1230 N/m worked example; direction preserved |
| `stability.inertiaForcePerLengthNM` | `unit-tested` | rho C_M (pi D^2 / 4) dU/dt closed form |
| `stability.liftForcePerLengthNM` | `unit-tested` | 922.5 N/m worked example |
| `stability.requiredSubmergedWeightNM` | `unit-tested` | 3628.5 N/m composed example; SF and 1/mu scaling |
| `stability.verdict` | `unit-tested` | inclusive >= boundary pass |
| `cable_route_consumer.consumeCableJson` | `unit-tested` | aden-djibouti fixture parses to 2-waypoint LayPlan with both real landings |
| `cable_route_consumer.loadCoordIndexFromJson` | `unit-tested` | landing-point-geo FeatureCollection -> id -> (lon, lat) lookup |
| `cable_route_consumer.greatCircleKm` | `unit-tested` | 1-degree-of-latitude meridian = pi * R / 180 ~= 111.195 km; spherical-law-of-cosines cross-check on real Aden-Djibouti coords |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `20/20 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: per-unit-length stability only; the kernel
  does not claim accuracy for long pipeline runs in soft-soil
  conditions or VIV-dominated regimes.
- Type-II missed risk guard: typed-error rejection for non-positive
  density, zero coefficient, zero friction.
- Type-III category guard: hydrodynamic-force + lateral-static-
  balance kernel only; not a VIV fatigue engine; not a free-span
  shoulder analyser; not a flexural-rigidity / lateral-buckle
  initiation calculator; not a pipe-wall strength check (compose
  with DNV-OS-F101 externally).

## What is not covered (v0.0.0)

- Long-term wave-statistics envelope.
- VIV fatigue.
- Free-span shoulder analysis.
- Soft-soil bottom-shape correction.
- Lateral-buckle initiation.
- Pipe-wall stress / DNV-OS-F101 strength.

## Cross-substrate wire (oceanman cable route consumer)

The `cable_route_consumer` module reads an oceanman per-cable JSON
record and emits a route-geometry-only `LayPlan`. Type-I overclaim
guard: a cable record is NOT a pipeline lay plan; the wire surfaces
the shared maritime route-geometry substrate, not equivalence. The
`depth_profile_present: false` flag is the load-bearing honest signal.
See `src/cable_route_consumer.zig` module comment for the full
shared-vs-divergent breakdown.

## Composition

- Input U, dU/dt from a wave-kinematics evaluator (compose with
  `yard-seakeeping-zig` Pierson-Moskowitz / JONSWAP -> Wheeler
  stretching at the seabed).
- Output W_required vs caller-supplied actual submerged weight
  closes the lateral stability gate.
