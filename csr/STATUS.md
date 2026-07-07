# Status

yard-csr-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `section_check.SteelGrade.k` | `unit-tested` | UR S4 table match: mild 1.00, ht32 0.78, ht36 0.72, ht40 0.66 |
| `section_check.permissibleStressMpa` | `unit-tested` | 175 / k for each grade |
| `section_check.evaluate` | `unit-tested` | Bulker condition (M_hog 3.0e6 kN*m, Z_net 19.5 m^3, mild steel) returns sigma_hog ~ 153.8 MPa < 175, verdict pass; overloaded condition returns fail; higher-grade steel raises permissible |
| `section_check.evaluate` input validation | `unit-tested` | Rejects non-positive Z, negative corrosion deduction, deduction >= Z |
| `section_check.aggregateVerdict` | `unit-tested` | Fail iff any condition fails; pass iff all pass |
| `section_check.Result.margin_*` | `unit-tested` | sigma_perm minus stress per mode |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `11/11 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: stress computations use a wide tolerance
  on the Hughes/Paik cross-check (~0.01 MPa) because the underlying
  rule values are 4-sig-fig published.
- Type-II missed risk guard: explicit error variants for non-positive
  Z, negative corrosion deduction, deduction larger than Z, invalid
  material factor.
- Type-III category guard: section-modulus combined-load check only.
  No buckling, no fatigue, no shear, no SOLAS damage stability.

## What is not covered (v0.0.0)

- Full CSR-BC&OT rule book.
- Combined yielding + buckling + fatigue check.
- Shear-stress check.
- Corrosion-deduction geometric computation from plate wastage.
- Wave-bending-moment computation (compose with yard-strength-zig).

## Validation against codex substrate

Formulas trace to
`~/codex/concepts/iacs-ur-s11-longitudinal-strength.md` and
`~/codex/sources/standards_machine_readable/iacs_ur_s11_longitudinal_strength.yaml`.
