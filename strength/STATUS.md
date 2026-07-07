# Status

yard-strength-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `ur_s11.waveCoefficient` | `unit-tested` | Exact analytic check at L=200 (9.75), L=300 (10.75), L=350 (10.75), L=500 (9.75); continuity at L=300 and L=350 boundaries within 1e-4; explicit rejection outside [90, 500] |
| `ur_s11.waveMomentHog` | `unit-tested` | Match against Hughes/Paik 2010 Ch.4 bulker worked example within 0.1 percent (~ 2,015,500 vs 2,016,000 kN*m); navigation-factor linearity; C_B floor at 0.60 |
| `ur_s11.waveMomentSag` | `unit-tested` | Match against Hughes/Paik 2010 Ch.4 bulker worked example within 0.1 percent (~ -2,127,800 vs -2,127,000 kN*m); negative-sign check |
| `ur_s11.SteelGrade` | `unit-tested` | k values match UR S4 table: mild = 1.00, HT32 = 0.78, HT36 = 0.72, HT40 = 0.66 |
| `ur_s11.permissibleStressMpa` | `unit-tested` | 175 / k scaling check |
| `ur_s11.minSectionModulus` | `unit-tested` | Derived Z = 11.517 m^3 for Hughes/Paik hog moment + mild steel; zero-moment rejection |
| `ur_s11.minMomentOfInertia` | `unit-tested` | Equation `I = 3 Z L` check |

## Constraint inheritance (C2)

Bound by Zig 0.16. Cannot claim v1.0 in semver spirit. Strongest
available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `16/16 tests pass`.

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Hughes/Paik cross-check is at the 0.1
  percent tolerance band; the published reference is a 4-sig-fig
  rounded value, so tighter tolerance would be a measurement-noise
  match, not a meaningful one.
- Type-II missed risk guard: C_B floor at 0.60 per UR S11 is enforced
  via `if (C_B < 0.60) cb_eff = 0.60`.
- Type-III category guard: this is a rule-formula evaluator, not a
  full structural-analysis tool. No buckling, no fatigue, no shear.

## What is not covered (v0.0.0)

- Shear stress and shear-permissible check.
- Buckling (plate, column, torsional) per UR S11 + RP-C201.
- UR S11A containership warping torsion + hatch corners.
- UR S25 corrosion deduction.
- Still-water bending moment integration from loading manual.

## Validation against codex substrate

Formulas transcribed from
`~/codex/sources/standards_machine_readable/iacs_ur_s11_longitudinal_strength.yaml`
and `~/codex/concepts/iacs-ur-s11-longitudinal-strength.md`.

Per `~/CONVENTIONS.md` C10, executable substrate is authoritative when
it diverges from prior narrative.
