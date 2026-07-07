# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `e26.Criticality`, `e26.CapabilityDomain`, `e26.EvidenceKind`
  enums.
- `e26.Control` and `e26.ComputerBasedSystem` typed structs.
- `e26.default_controls` representative 8-control set.
- `e26.evaluateCBS` allocator-free harness with typed CBSReport.
- 9-test unit suite including per-criticality control applicability,
  missing-evidence detection, and the critical-CBS backup-record
  cross-control failure case.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
