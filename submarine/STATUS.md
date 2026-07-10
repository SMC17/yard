# Status

yard-submarine-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2. 40/40 tests pass.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `pressure_hull` | `unit-tested` | von Mises buckling; yield collapse; crush depth @ SF |
| `dive` | `unit-tested` | W−B equilibrium; ascent rate ∝ √F_net |
| `ballast` | `unit-tested` | MBT capacity; reserve buoyancy; trim transfer mass |

Evaluation logic `unit-tested`. Seawater-density depth profile and
simplified deco-stop fits flagged `claimed`. Defensive/commercial-
research scope only.