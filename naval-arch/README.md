# yard-naval-arch

Shared types and units for yard composition workflows.

**Proof level:** `unit-tested`

## What it does

- **`PrincipalParticulars`** — L, B, T with L/B and B/T ratios.
- **`LoadingCondition`** — KG and rectangular tank list for free-surface
  correction.
- **`Hydrostatics`**, **`StabilitySummary`**, **`GzSample`**, **`IsCodeResult`**
  — interchange structs for compose/ and examples/ outputs.
- **`ValidityFlags`** — assumption tracking (`wall_sided_assumption_valid`,
  `free_surface_applied`, `outside_validity_envelope`, etc.) for agent and model
  outputs.
- **`ProofLevel`** — inherited proof vocabulary (`unit_tested`,
  `cross_validated`, `benchmark_hull`, …).
- **`units`** — deg/rad and knots/m/s conversions.
- **`PhysicalConstants`** — seawater density, g, ν defaults per validation
  fixtures.

## What it is not

Not a compute primitive. Primitive modules (`hydro`, `stability`, `resistance`,
etc.) do not import this package — only `compose/` and `examples/` use it as
the interchange contract. Not a schema registry for external databases or a
regulatory rule engine.

## Build and test

```sh
zig build test
```

## License

Apache-2.0. See `LICENSE`.