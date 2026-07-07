# yard-naval-arch

Shared types and units for yard composition workflows.

**Proof level:** `unit-tested`

## Types

- `PrincipalParticulars` — L, B, T
- `LoadingCondition` — KG + tank list
- `Hydrostatics`, `StabilitySummary`, `IsCodeResult`
- `ValidityFlags` — assumption tracking for agent/model outputs

Primitive modules do not import this package. Only `compose/` and `examples/` do.

License: Apache-2.0.
