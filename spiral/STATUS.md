# Status

yard-spiral-zig v0.1.0. Pre-1.0; bound by Zig 0.16 per `~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `stages` Evans 1959 loop | `unit-tested` | 10-stage enum + ordering |
| `orchestrator.runSpiral` | `unit-tested` | multi-loop convergence on GM/power |
| `orchestrator.runStage` | `unit-tested` | wires hydro/stability/resistance/ittc78/fossen |
| `optimizer` GA + gradient | `unit-tested` | population evolution + finite differences |
| `codegen.generateNavalCode` | `unit-tested` | emits compilable Zig skeleton |
| `dp_feedback.estimate` | `unit-tested` | coupled DP under Hs=2 excursion cap |
| `orchestrator.tank_hull` ingest | `benchmark_hull` | KCS/KVLCC2 tank C_T + Prohaska + ITTC-78 |

## Architecture

Evans Ship Design Spiral as executable workflow engine. Multi-fidelity stages
select approximation depth. Similarity-native model→ship extrapolation via
`yard-similarity` + `yard-ittc78`.

## Composition

- Consumes `yard-hydro`, `yard-stability`, `yard-resistance`, `yard-similarity`,
  `yard-ittc78`, `yard-fossen-6dof`.
- Exposed via `compose/design_spiral` and `examples/design-spiral-wigley`.