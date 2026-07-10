# Status

yard-naval-arch-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per `~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `PrincipalParticulars` | `unit-tested` | L/B, B/T ratio closures |
| `ValidityFlags` | `unit-tested` | EnumSet over assumption / envelope flags |
| `ProofLevel` | `unit-tested` | unit_tested … class_society enum contract |
| `PhysicalConstants` | `unit-tested` | seawater defaults per validation_fixtures |
| `units` deg/rad/knots | `unit-tested` | round-trip conversion checks |

## Composition

Interchange contract for `compose/` and `examples/` only. Primitive modules do not import this package.