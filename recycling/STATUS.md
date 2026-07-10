# Status

yard-recycling-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `hkc` | `unit-tested` | capacity utilisation; entry-year gate; EU SRR flag |
| `ihm` | `unit-tested` | HKC max-fraction verdicts; failing-entry count |
| `recovery` | `unit-tested` | per-category LDT fractions sum to unity |

37/37 tests pass. HKC entry-year + IHM max-fraction table + LDT
recovery fractions all flagged `claimed`; evaluation logic
`unit-tested`.