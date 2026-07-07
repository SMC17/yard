# Status

yard-tug-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `bollard.TugType.bollardCoefficient` | `claimed` | 0.10 / 0.12 / 0.13 / 0.135 kN/kW per Carlton 2018 + manufacturer rules of thumb |
| `bollard.bollardPullKN` | `unit-tested` | linear scaling; ASD at 2 MW = 240 kN |
| `bollard.bollardPullToTonnesForce` | `unit-tested` | division by 9.80665 |
| `bollard.thrustToWeightRatio` | `unit-tested` | BP / (m g) closed form |
| `indirect.effectiveForceKN` | `unit-tested` | BP sin(beta) cos(theta); 30 deg case = BP/2; sign-axis limits |
| `indirect.steeringMomentKNm` | `unit-tested` | F L sin(theta) closed form |
| `indirect.brakingForceKN` | `unit-tested` | beta = 45 deg gives BP / sqrt(2) |
| `effective.bollardAtSpeedKN` | `unit-tested` | linear degradation; V_max clamps to zero |
| `effective.typicalVMaxMPerS` | `claimed` | 5 / 7 / 6.5 / 8 m/s typical values per manufacturer brochures |
| `effective.assistanceVerdict` | `unit-tested` | inclusive >= boundary pass |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `33/33 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: bollard-coefficient and V_max tables
  flagged `claimed`; per-vessel manufacturer data should override.
  The kernel does not claim accuracy beyond the standard rule-of-
  thumb regression.
- Type-II missed risk guard: typed-error rejection for non-positive
  power, BP, V_max, m_tug, invalid heel/towline angles, negative
  speed.
- Type-III category guard: tug-performance kernel only; not a
  dynamic-tension / shock-load engine; not a multi-tug allocation
  optimiser; not a 3-DOF tug-control-law evaluator.

## What is not covered (v0.0.0)

- Assisted-ship wake / squat interaction.
- Tow-line dynamic-tension envelope.
- Manufacturer-specific bollard catalog ingestion.
- Multi-tug allocation across assisted vessel.
- Wind / current compensation.
- Tug-control-law evaluation.

## Composition

- Inputs P_brake from `yard-engine-zig` brake-power output.
- Output BP couples to assisted-ship resistance from
  `yard-resistance-zig` for a tow / push assistance check.
- Tow-line angle theta couples to a controller setpoint.
