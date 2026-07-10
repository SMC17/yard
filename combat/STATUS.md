# Status

yard-combat-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2. 42/42 tests pass.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `rcs` | `unit-tested` | flat-plate, sphere, trihedral; radar range ∝ σ^(1/4) |
| `weapon` | `unit-tested` | recoil impulse, muzzle energy, VLS deck pressure |
| `magazine` | `unit-tested` | STANAG 4439 QD K·NEW^(1/3); MCE aggregation |

Evaluation logic `unit-tested`. STANAG 4439 K-factors and MIL-STD
constants flagged `claimed`. Defensive / situational-awareness scope
only; offensive targeting tasks are not implemented.