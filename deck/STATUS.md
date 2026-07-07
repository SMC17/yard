# Status

yard-deck-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `crane.heelingMomentNm` | `unit-tested` | SWL g r * 1000 closed form; linear scaling |
| `crane.swlFromChart` | `unit-tested` | midpoint = arithmetic mean; exact anchor; clamping at both ends |
| `crane.swlMomentLimit` | `unit-tested` | SWL r = constant; 100 000 t at r=10 m, M_max = 9.81 GNm |
| `tipping.rightingMomentNm` | `unit-tested` | Delta g GM sin(phi) closed form |
| `tipping.equilibriumHeelRad` | `unit-tested` | zero at M=0; pi/2 at M_critical; overturning detected |
| `tipping.tippingVerdict` | `unit-tested` | pass at small M; fail at large M |
| `dynamic.dynamicAmplificationFactor` | `unit-tested` | 1 + a_v / g closed form |
| `dynamic.dynamicLoadN` | `unit-tested` | SWL g DAF closed form |
| `dynamic.waveDrivenAccelerationMPS2` | `claimed` | 1.2 Hs / T_z^2 indicative DNV-RP-N103 envelope; per-vessel calibration deferred |
| `dynamic.deratedSWL` | `unit-tested` | SWL / DAF closed form |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `35/35 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: the wave-driven acceleration formula is
  an indicative envelope; for a specific crane vessel and sea-state
  the caller composes the full RAO + spectrum convolution via
  `yard-strip-theory-zig` and `yard-rao-spectrum-zig`. The formula
  is flagged `claimed`.
- Type-II missed risk guard: typed-error rejection for non-positive
  SWL, outreach, GM, displacement, gravity, T_z; invalid heel angle;
  chart length errors. Overturning is signalled by an explicit
  Error.InvalidAngle from `equilibriumHeelRad`.
- Type-III category guard: SWL / tipping / DAF kernel only; not a
  structural-FE crane analyser; not a wire-fatigue calculator; not
  a multi-fall block tackle solver; not a knuckle-boom kinematic
  engine.

## What is not covered (v0.0.0)

- Crane structural FE (boom / pedestal / slewing ring).
- Multi-fall block tackle wire tension.
- Two-block / over-hoist anti-collision.
- Wire-fatigue calculation.
- Knuckle-boom kinematics.
- Personnel-transfer crane envelope.

## Composition

- Inputs Delta, GM from `yard-stability-zig` and `yard-hydro-zig`.
- Input a_v from `yard-rao-spectrum-zig` significant vertical
  acceleration or `dynamic.waveDrivenAccelerationMPS2` envelope.
- Output tipping verdict composes with `yard-stir-zig` for the full
  intact-stability check including the crane heeling moment.
