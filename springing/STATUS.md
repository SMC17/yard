# Status

yard-springing-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `hull_girder.twoNodeBendingHz` | `unit-tested` | sqrt(I), 1/sqrt(Delta), 1/L^(3/2) scaling laws verified |
| `hull_girder.phi_schlick_merchant_si` | `claimed` | 32000 SI coefficient for typical merchant ships per Schlick 1894; supplier / ship-type calibration deferred |
| `hull_girder.twoNodeBendingRps` | `unit-tested` | 2 pi closed form |
| `hull_girder.twoNodePeriodSec` | `unit-tested` | 1 / f closed form |
| `whipping.dampedAngularFrequencyRps` | `unit-tested` | omega_n sqrt(1 - zeta^2); zeta = 0 returns omega_n |
| `whipping.freeDecayAmplitude` | `unit-tested` | x(0) = 1; envelope monotone over multiple half-periods |
| `whipping.logarithmicDecrement` | `unit-tested` | 2 pi zeta / sqrt(1 - zeta^2) closed form |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `18/18 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Schlick coefficient flagged `claimed`.
  Per-ship calibration via towing-tank or strain-gauge measurements
  produces a sharper phi.
- Type-II missed risk guard: typed-error rejection for zero
  displacement / I / L / phi, overdamped zeta >= 1, negative time.
- Type-III category guard: two-node-mode and free-decay envelope
  kernel only; not a multi-mode transfer-matrix solver; not a
  slamming-pressure engine; not a long-term Hs / Tp statistical
  envelope; not a fatigue accumulator.

## What is not covered (v0.0.0)

- Higher-mode (4-node, 6-node) frequencies.
- Fluid added-mass / coupling.
- Wave-induced springing steady-state response.
- Slamming-pressure load.
- Long-term Hs / Tp envelope.
- Whipping fatigue accumulation.

## Composition

- Input I_v and Delta from `yard-strength-zig` and
  `yard-hydro-zig`.
- Output omega_n couples to `yard-rao-spectrum-zig` as a tuned-mass
  resonance band that must be avoided by wave-encounter frequencies
  (parametric-roll-style avoidance also in `yard-stir-zig`).
- Whipping envelope feeds `yard-csr-fatigue-zig` stress-range
  amplification for fatigue post-processing.
