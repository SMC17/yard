# Status

yard-propulsion-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `wageningen.kT` polynomial | `unit-tested` | Sign tests at J=0 and large J; monotonicity test 11-step; P/D-effect qualitative test; deterministic-call test; term-count assertion (39 terms); regression-lock at J=0 B4-70 P/D=1.0 |
| `wageningen.kQ` polynomial | `unit-tested` | Positive at moderate J; P/D-effect qualitative test; term-count assertion (47 terms); regression-lock at J=0.6 B4-70 P/D=1.0 |
| `wageningen.etaO` open-water efficiency | `unit-tested` | Peak-at-intermediate-J test; absolute peak value 0.5 < eta < 0.75 for B4-70 P/D=1.0 |
| `wageningen.deltaKT` Reynolds correction | `unit-tested` | Magnitude is small (`abs(dkt) < 0.05`) at typical Rn |
| `wageningen.deltaKQ` Reynolds correction | `unit-tested` | Magnitude is small at typical Rn |
| `wageningen.validate` envelope check | `unit-tested` | Accept inside; reject outside on Z, P/D, A_E/A_0, J, Rn; explicit-error tagging |
| Coefficient table accuracy | `unverified-on-clean-print` | 11 rows tagged `// [ocr]` carry values from OCR-ambiguous scans; canonical values per downstream implementations; clean-print verification deferred |

## Coefficient rows requiring clean-print verification

Per the source codex note at `~/codex/sources/naome_data_substrate_deep.md`
Section 2A, the following rows had OCR-ambiguous glyphs on the scan ingest:

**K_T table (Oosterveld 1975 Table 5 left column):**

| Row | Coefficient (canonical) | Source OCR rendered |
|---|---|---|
| 4 | +0.158114 | `•0,158114` |
| 13 | +0.0109619 | `+ 0.OIO96!9` |
| 16 | -0.00132718 | `-0,0013:718` |
| 28 | -0.00410798 | `-O.0O4I079!` |
| 32 | -0.000560528 | `-O.O0O56O52!` |

**K_Q table (Oosterveld 1975 Table 5 right column):**

| Row | Coefficient (canonical) | Source OCR rendered |
|---|---|---|
| 3 | -0.032241 | `-0.03224!` |
| 7 | -0.0885381 | `-O.O8S538I` |
| 17 | +0.0161886 | `-; 0.0161886` (sign also ambig) |
| 18 | +0.00318086 | `-; O.O0318086` (sign also ambig) |
| 28 | +0.00110903 | `-r O-OOI 10903` |
| 29 | -0.000313912 | `-O.OO03139I2` |
| 35 | +0.0033418 | `+ 0.00334 J6B` |
| 43 | -0.0001843 | `-O.O00IS43` |
| 44 | -0.000425399 | `-0.0004:53»` |
| 45 | +0.0000869243 | `~ O.OO00869243` |

Resolution path to `unit-tested` for the coefficient table: cross-check
against a clean print of Bernitsas-Ray-Kinley 1981 (UMich Report 237)
or against an independent published implementation (FreeCAD-Ship
Wageningen module, NSMB-MARIN-derived code, or an academic propeller
design tool). Once external agreement at the f64 round-off level is
documented, the entire coefficient table moves to `unit-tested` and
the table above is preserved as a historical-narrative entry per C7.

## Constraint inheritance (C2)

Bound by Zig 0.16. Cannot claim v1.0 in semver spirit. Strongest
available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `20/20 tests pass`.

Verification command:

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: regression lock tests use the value the
  polynomial currently produces, NOT an asserted published value.
  Absolute correctness vs Bernitsas 1981 is explicitly deferred to
  external verification.
- Type-II missed risk guard: the OCR-ambiguous rows are enumerated;
  they are not silently assumed correct.
- Type-III category guard: this is a propeller-coefficient evaluator,
  not a propeller-selection optimizer, not a powering-chain extrapolator,
  not a cavitation analyzer. Cross-port composition produces those.

## What is not covered (v0.0.0)

- Open-water test extrapolation (ITTC-78 chain).
- Cavitation diagrams.
- Off-design / oblique flow.
- Ducted propellers (Ka-series, Kaplan-series).
- Controllable-pitch propellers.
- Pre-swirl + post-swirl propellers.
- Propeller-hull interaction (wake fraction, thrust deduction; PIAS / Holtrop).

## Validation against codex substrate

Coefficients trace to `~/codex/sources/naome_data_substrate_deep.md`
Section 2A. Concept note at
`~/codex/concepts/wageningen-b-series-propeller-coefficients.md`.

Per `~/CONVENTIONS.md` C10, executable substrate is authoritative when
it diverges from prior narrative. The lock-in regression values in
the tests are the current executable truth.
