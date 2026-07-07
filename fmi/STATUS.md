# Status

yard-fmi-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `model_description.Causality.name` | `unit-tested` | Exact-string match against FMI 3.0 spec names (parameter, calculatedParameter, input, output, local, independent) |
| `model_description.Variability.name` | `unit-tested` | Exact-string match against FMI 3.0 spec names |
| `model_description.validate` | `unit-tested` | Empty-list rejection; duplicate value reference rejection; duplicate name rejection |
| `model_description.write` | `unit-tested` | Non-empty output; contains fmiVersion 3.0 and model name; per-variable Float64 element emitted; output variables placed in ModelStructure; start value rendered when set; CoSimulation interface declared; XML tags matched (open + close) |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `10/10 tests pass`.

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: tests assert structural presence
  (substring matches) rather than full FMI schema validation
  against the published XSD. A schema-validated test would be
  stronger; for v0.0.0 the structural checks bound the claim.
- Type-II missed risk guard: explicit error variants for empty
  list, duplicate value references, duplicate names, allocation
  failure.
- Type-III category guard: XML generation only. No FMU archive
  builder. No C ABI runtime. No FMU consumer.

## What is not covered (v0.0.0)

- FMU ZIP archive packaging.
- C ABI runtime (fmi3DoStep, fmi3GetReal, fmi3SetReal).
- Non-Float64 variable types.
- Structural parameters.
- Clocks, terminals, events.
- ModelExchange and ScheduledExecution interfaces.
- FMI XSD schema validation of generated output.

## Validation against codex substrate

Concept note at
`~/codex/concepts/f9-fmi-3-osp-cosim-envelope-architecture.md`.
