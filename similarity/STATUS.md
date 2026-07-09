# Status

yard-similarity-zig v0.1.0. Pre-1.0; bound by Zig 0.16 per `~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `scale` geometric/kinematic/dynamic | `unit-tested` | λ³ volume, λ² area, Froude/Reynolds closure |
| `froude` | `unit-tested` | Fn invariance under geometric + kinematic scaling |
| `reynolds` | `unit-tested` | Rn scaling law at constant ν ratio |
| `extrapolation` C_R copy | `unit-tested` | ITTC-78 step 6 residual transfer |

## Composition

- Feeds `yard-ittc78-zig::extrapolate` model/ship scale structs.
- Used by `yard-spiral-zig` and `compose/design_spiral` workflows.