# Status

yard-port-engineering-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `breakwater` | `unit-tested` | transmission K_t; Hudson W_50; Iribarren run-up |
| `channel` | `unit-tested` | PIANC UKC fractions; Barrass squat; two-way width |
| `basin` | `unit-tested` | Helmholtz period; closed/open seiche modes |

Evaluation logic `unit-tested`. PIANC UKC fractions and
manoeuvring-class width factors flagged `claimed`. Hudson K_D values
caller-supplied. 40/40 tests pass.