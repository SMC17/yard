# yard-spiral-zig

Proof level: `unit-tested`

Evans 1959 Ship Design Spiral orchestrator wiring yard primitives into
iterative, auditable design loops with similarity-native model testing.

## What it does

- **`stages`** — ten Evans spiral stages; fidelity levels `low` / `mid` / `high`
  / `ultra` select approximation depth per loop.
- **`orchestrator`** — `runSpiral` / `runStage`: dimensions, Holtrop
  resistance, tank C_T ingest for KCS/KVLCC2 via `yard-benchmark`, ITTC-78
  model extrapolation, box-barge stability proxy, seakeeping stubs, benchmark
  cross-checks; convergence on GM and effective power.
- **`optimizer`** — genetic algorithm and finite-difference gradient refinement;
  Pareto front over power, significant heave, and GM.
- **`codegen`** — emits a compilable Zig simulator skeleton from converged
  design parameters.
- **`dp_feedback`** — time-domain DP under ITTC-PM irregular sway for
  high-fidelity operability feedback (mirrors `compose/coupled_dp_waves`
  without importing `yard-compose`).

## What it is not

Not a preliminary design tool suitable for contract delivery. Structure,
arrangements, and cost stages are lightweight placeholders. `ultra` fidelity
declares FMI co-simulation hooks but does not ship external coupling. Not
regulatory approval, class society plan review, or build-for-production design.

## Build and test

```
zig build test --summary all
```

## License

Apache-2.0. See `LICENSE`.