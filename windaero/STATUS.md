# Status

yard-windaero-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `blendermann.peakCoefficients` | `claimed` | container 0.55 / 0.85 / 0.13 from Blendermann 1996 catalogue summary; tanker / bulk / passenger / generic relative values consistent with the original report; per-ship calibration deferred |
| `blendermann.longitudinalCoefficient` | `unit-tested` | C_X_max cos(eps) closed form; head/beam/stern verified |
| `blendermann.lateralCoefficient` | `unit-tested` | C_Y_max sin(eps); sign reversal across centreline |
| `blendermann.yawMomentCoefficient` | `unit-tested` | C_N_max sin(2 eps); peak at eps = pi/4 |
| `blendermann.{longitudinal,lateral}ForceN`, `yawMomentNm` | `unit-tested` | V^2 scaling; cardinal-direction limits |

## Coverage caveat

Single-mode trigonometric approximation; the full Blendermann report
provides multi-mode Fourier coefficients that capture the
asymmetric-superstructure peak shifts. The kernel uses the
single-mode shape as a first-order screening primitive.

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `13/13 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: single-mode coefficients; the kernel does
  not claim asymmetric-superstructure peak-shift accuracy. Peak
  catalogue flagged `claimed` until ship-specific calibration is
  performed.
- Type-II missed risk guard: typed-error rejection for non-positive
  density / speed / area / length, eps outside [-pi, pi].
- Type-III category guard: ship aerodynamic-force kernel only; not
  a heeling-moment integrator (compose with `yard-stir-zig`); not
  a gust-spectrum convolver; not a fixed-platform / jacket wind
  load model.

## What is not covered (v0.0.0)

- Multi-mode Fourier coefficients.
- Heeling moment from wind centre-of-pressure.
- Turbulence / gust spectrum.
- Atmospheric boundary-layer gradient.
- Fixed-platform wind coefficients.
- Anti-rolling / sail-augmentation profiles.

## Composition

- Input `V_apparent` from a meteorological boundary-layer model and
  the ship-motion ground velocity.
- Output X, Y, N feed `yard-fossen-6dof-zig` 6-DOF state-space as
  wind-disturbance forcing.
- The same A_L, A_T, L_OA inputs couple to `yard-stir-zig::dead_ship`
  for the static wind-heel calculation.
