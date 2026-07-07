# Status

yard-resistance-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `ittc57.cF` | `unit-tested` | Match against textbook values at Rn = 5e6 (0.003396) and Rn = 1.5e9 (0.001457); exact value at Rn = 1e6 (0.0046875); strict monotonic decrease across Rn = 1e6 to 1e10; positive across the validity range; explicit error on Rn <= 0 and Rn < 1e5 |
| `ittc57.reynolds`, `ittc57.rFPerArea` | `unit-tested` | Unit-input check; V^2 scaling check |
| `holtrop.formFactor1984` | `unit-tested` | (1 + k1) within typical cargo envelope (1.05 to 1.50); deterministic call; c_stern shift moves the value in the expected direction (V-shaped lower, U-shaped higher) |
| `holtrop.halfAngleOfEntrance` | `unit-tested` | Positive and below 89 degrees on the cargo fixture |
| `holtrop.waveResistance` | `unit-tested` | Positive at moderate Fn; monotonically increases with V in low-Fn band; transition continuity at Fn = 0.4 and Fn = 0.55 (within 5 percent) |
| `holtrop.totalResistance` | `unit-tested` | Positive and dominated by friction at low Fn; monotonic in V; regression-lock at V = 6 m/s on cargo fixture (bounded between 1e4 and 1e6 Newtons) |
| Holtrop coefficient transcription | `cross-verified-via-two-open-impl` | c17, m3 verified against FreeCAD-Ship + aletirelli implementations; c1, m1, m4, lambda, c14, c15, c16, c7 verified against three open Python implementations. Primary Holtrop 1984 ISP 31 still blocked at IOS Press / TU Delft. |

## Constraint inheritance (C2)

Bound by Zig 0.16. Cannot claim v1.0 in semver spirit. Strongest
available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `21/21 tests pass`.

Verification command:

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: the totalResistance regression-lock test
  uses a wide bound (1e4 to 1e6 N) rather than a tight numerical
  match. The implementation produces a specific value today; the
  bound catches gross regressions without making absolute correctness
  claims against unobtained tank data.
- Type-II missed risk guard: validity envelope is documented in
  README; v0.0.0 does not enforce it at runtime. A future v0.x will
  add `holtrop.validate` analogous to `forge_propulsion.wageningen.validate`.
- Type-III category guard: this is a resistance evaluator, not a
  powering-chain extrapolator, not a propeller selector, not a
  cavitation analyzer.

## What is not covered (v0.0.0)

- Bulb resistance (R_B). c2 returns 1.0 (the A_BT = 0 case).
- Immersed-transom resistance (R_TR). c5 returns 1.0 (the A_T = 0 case).
- Model-ship correlation allowance (R_A).
- Appendage resistance (R_app).
- Propulsion-factor chain (w, t, eta_R).
- Reynolds correction below 1e5 (laminar / transitional regime).
- Validity-envelope runtime check.

## Validation against codex substrate

Coefficients and formulas trace to
`~/codex/sources/naome_data_substrate_deep.md` Section 2B. Concept
note at `~/codex/concepts/holtrop-mennen-resistance-prediction.md`
and `~/codex/concepts/ittc-57-and-ittc-78-extrapolation.md`.

Per `~/CONVENTIONS.md` C10, executable substrate is authoritative when
it diverges from prior narrative.
