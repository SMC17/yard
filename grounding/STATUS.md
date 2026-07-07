# Status

yard-grounding-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `pedersen_zhang.kineticEnergyJ` | `unit-tested` | 0.5 (1 + mu_x) m V^2 closed form to 1 J on 189 MJ value |
| `pedersen_zhang.meanHorizontalForceN` | `unit-tested` | sigma_y t h_r C_g closed form on 15.228 MN value |
| `pedersen_zhang.C_g_smooth_rock` | `claimed` | 1.62 per Pedersen-Zhang 2000 smooth-rock case; sharp-asperity ~2.0 and blunt ~1.3 deferred |
| `pedersen_zhang.dampageLengthM` | `unit-tested` | E/F closed form to 1e-12 |
| `pedersen_zhang.analyseGrounding` | `unit-tested` | three-step composition; V^2 scaling exact |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Pedersen-Zhang mean-force formula is the
  smooth-rock case (`C_g = 1.62`). Sharp / blunt asperities require
  different shape factors; the kernel does not silently re-use the
  smooth-rock factor outside that regime.
- Type-II missed risk guard: typed-error rejection for negative
  velocity, zero plate thickness, zero rock height, non-positive
  yield strength.
- Type-III category guard: simplified energy-force balance only;
  not a transient impact-load engine; not a double-bottom rupture
  classifier; not an oil-outflow estimator.

## What is not covered (v0.0.0)

- Bottom-shape (rock height) probabilistic envelope.
- Conical / parabolic asperity C_g.
- Transient impact loads.
- Tank rupture / spill volume estimator.
- Double-bottom intact / pierced verdict.
- Stranding-stability follow-on.

## Composition

- Output `damage_length_m` composes with the bottom-plate
  arrangement in `yard-csr-zig` to identify damaged transverse
  sections; the damage-stability follow-on couples to
  `yard-stability-zig` damage section.
- Composes with `yard-collision-zig::minorsky.absorbedEnergyMJ` for
  the equivalent collision-class regression on the same E_abs.
