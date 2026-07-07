# Status

yard-collision-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `minorsky.resistanceFactorM3` | `unit-tested` | sum t_i A_i closed form |
| `minorsky.absorbedEnergyMJ` | `unit-tested` | intercept 32.7 at R_T = 0; slope 47.1 per m^3; 503.7 at R_T = 10 |
| `kinetic.effectiveMassKg` | `unit-tested` | mu=0 returns m; mu=1.4 returns 2.4 m |
| `kinetic.kineticEnergyJ` | `unit-tested` | 0.5 m V^2 |
| `kinetic.kineticEnergyWithAddedMassJ` | `unit-tested` | (1+mu) scaling |
| `kinetic.rightAngleAbsorbedEnergyJ` | `unit-tested` | equal-mass = 0.5 E_k_a; mass-asymmetric limits |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `20/20 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Minorsky regression is explicitly the 1959
  right-angle empirical correlation; the kernel does not claim a
  generalised collision-physics model. Pedersen-Zhang super-element
  approach is listed under "what is not covered" rather than silently
  approximated.
- Type-II missed risk guard: input rejection prevents zero or
  negative thickness / mass / velocity / mu from yielding a
  misleading R_T or energy.
- Type-III category guard: collision-energy regression and rigid-body
  energy partition only; not a structural-deformation FE solver;
  not a tank-rupture predictor; not a probabilistic risk model;
  not an oblique-angle decomposition.

## What is not covered (v0.0.0)

- Pedersen-Zhang grounding / raking damage model.
- Super-element FE deformation engine.
- Tank-rupture / spill-volume estimator.
- Oblique-angle collision decomposition.
- Probabilistic collision-frequency analysis.
- Damage-stability follow-on (compose with `yard-stability-zig`).

## Composition

- `rightAngleAbsorbedEnergyJ` output equals the total energy that
  must be absorbed by structural damage. Equating this to
  `minorsky.absorbedEnergyMJ(R_T) * 1e6` yields the predicted R_T,
  which closes the loop with structural damage volume.
- Output R_T composes externally with damage-stability verification
  via `yard-stability-zig`.
