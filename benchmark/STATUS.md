# Status

yard-benchmark-zig v0.1.0. Pre-1.0; bound by Zig 0.16.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `hulls` standard fixtures | `unit-tested` | Wigley, KCS, KVLCC2, Series-60 Cb=0.60 |
| `harness.runAll` | `unit-tested` | hydrostatics, similarity/ITTC-78 cross-check, Holtrop envelope |
| `harness` KCS resistance | `cross_validated` | positive R_T at SIMMAN design speed |
| `tank_data` KCS/KVLCC2 series | `benchmark_hull` | SIMMAN/Tokyo workshop C_T(Fn) points |
| `tank_extrapolate` | `cross_validated` | KCS P_E rel err <2%; harness ≤5% vs ITTC-78 |

## Composition

Feeds spiral validation loops and `examples/benchmark-validation`.