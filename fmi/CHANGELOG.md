# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `model_description.Causality` and `model_description.Variability`
  enums.
- `model_description.Float64Variable` typed variable declaration.
- `model_description.Description` typed FMU description.
- `model_description.validate` structural-correctness checker.
- `model_description.write` modelDescription.xml serializer to an
  ArrayList(u8).
- 10-test unit suite covering enum-string spec correctness,
  duplicate detection, and structural-substring presence in the
  generated XML.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
