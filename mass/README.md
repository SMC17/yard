# yard-mass-zig

Proof level: `unit-tested`

yard-mass-zig is a Zig 0.16 IACS UR E26 + UR E27 cyber-resilience
compliance harness. A Computer-Based System (CBS) is evaluated against
a typed control set; the harness reports per-control verdicts and the
missing evidence for any failing control.

## What it does

- `e26.Criticality` enum (non_essential, essential, critical) with
  numeric ordering.
- `e26.CapabilityDomain` enum (identify, protect, detect, respond,
  recover) per NIST CSF and UR E26.
- `e26.EvidenceKind` enum (asset_register_entry, risk_assessment,
  access_control_policy, network_segmentation_record, monitoring_log,
  incident_response_plan, backup_record, periodic_audit_report).
- `e26.Control` typed struct with id, domain, applies_at_or_above,
  required_evidence.
- `e26.ComputerBasedSystem` typed CBS struct.
- `e26.default_controls` a representative 8-control set covering the
  five capability domains.
- `e26.evaluateCBS(cbs, controls, verdicts_out, missing_buf)` returns
  a typed `CBSReport` with per-control verdict and missing evidence
  list. Allocator-free; caller supplies output buffers.

## What it is not (v0.0.0)

- No real-world UR E26 / UR E27 full control catalog (the included
  set is a representative subset for the harness shape, not a
  certified rule book reproduction).
- No YAML / JSON config loader (controls are encoded as Zig data;
  caller can extend the array).
- No equipment-type-approval registry (UR E27 manufacturer side).
- No CBS criticality classifier (caller assigns criticality).
- No DNV CyberSecure, ABS CyberSafety, or LR ShipRight Cyber
  notation cross-walks.
- No risk-scoring quantitative model.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 9/9 tests passed`.

## Public API

```zig
const yard = @import("yard_mass");

const evidence = [_]yard.e26.EvidenceKind{
    .asset_register_entry, .risk_assessment, .access_control_policy,
    .network_segmentation_record, .monitoring_log, .incident_response_plan,
    .backup_record, .periodic_audit_report,
};
const cbs: yard.e26.ComputerBasedSystem = .{
    .id = "CBS-001", .name = "Bridge navigation",
    .criticality = .critical, .evidence = &evidence,
};
var verdicts: [16]yard.e26.ControlVerdict = undefined;
var missing: [32]yard.e26.EvidenceKind = undefined;
const r = try yard.e26.evaluateCBS(cbs, &yard.e26.default_controls, &verdicts, &missing);
// r.overall_pass, r.verdicts[i].pass, r.verdicts[i].missing.
```

## Validation

- Criticality enum ordering: critical > essential > non_essential.
- Non-essential CBS sees only the asset-register-entry control.
- Essential CBS missing risk-assessment fails on E26-ID-2 with
  the missing evidence list correctly populated.
- Critical CBS triggers the additional E26-PR-2 (backup-record)
  requirement; 8 controls apply.
- Critical CBS missing backup fails BOTH E26-PR-2 and E26-RC-1
  (the recovery domain also requires backup_record).
- Output buffer-size mismatch rejection.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IACS Unified Requirement E26 (Cyber Resilience of Ships).
- IACS Unified Requirement E27 (Cyber Resilience of On-Board Systems
  and Equipment).
- IEC 62443-3-3 (System Security Requirements and Security Levels).
- NIST Cybersecurity Framework 2.0 (2024).
- Codex cross-references at
  `~/codex/concepts/iacs-ur-e26-cyber-resilience-of-ships.md` and
  `~/codex/concepts/iacs-ur-e27-cyber-resilience-on-board-systems.md`.

## License

Apache-2.0.
