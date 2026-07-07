// IACS UR E26 + UR E27 cyber-resilience compliance harness.
//
// UR E26 (Cyber Resilience of Ships) applies to newbuildings
// contracted on or after 1 July 2024 with on-board computer-based
// systems (CBS). UR E27 (Cyber Resilience of On-Board Systems and
// Equipment) applies to the equipment supplied to those ships.
//
// Both require, per CBS or equipment:
//   - asset register entry
//   - risk-based criticality classification
//   - implementation of capability-domain controls (Identify, Protect,
//     Detect, Respond, Recover)
//   - evidence of control implementation
//   - periodic verification
//
// This v0.0.0 encodes a small representative control set per
// criticality and checks that each applicable control has the required
// evidence kinds.
//
// Source: ~/codex/concepts/iacs-ur-e26-cyber-resilience-of-ships.md.

const std = @import("std");

pub const Error = error{
    EmptyAssetRegister,
    UnknownEvidence,
};

pub const Criticality = enum {
    non_essential,
    essential,
    critical,
};

pub const CapabilityDomain = enum {
    identify,
    protect,
    detect,
    respond,
    recover,
};

pub const EvidenceKind = enum {
    asset_register_entry,
    risk_assessment,
    access_control_policy,
    network_segmentation_record,
    monitoring_log,
    incident_response_plan,
    backup_record,
    periodic_audit_report,
};

pub const Control = struct {
    id: []const u8,
    domain: CapabilityDomain,
    applies_at_or_above: Criticality,
    required_evidence: []const EvidenceKind,
};

pub const ComputerBasedSystem = struct {
    id: []const u8,
    name: []const u8,
    criticality: Criticality,
    evidence: []const EvidenceKind,
};

pub const ControlVerdict = struct {
    control_id: []const u8,
    pass: bool,
    missing: []const EvidenceKind,
};

pub const CBSReport = struct {
    cbs_id: []const u8,
    verdicts: []ControlVerdict,
    overall_pass: bool,
};

/// A small default control set covering the five capability domains.
/// In a real deployment this comes from a YAML or external config; here
/// it is hard-coded for the v0.0.0 harness.
pub const default_controls = [_]Control{
    .{
        .id = "E26-ID-1",
        .domain = .identify,
        .applies_at_or_above = .non_essential,
        .required_evidence = &.{.asset_register_entry},
    },
    .{
        .id = "E26-ID-2",
        .domain = .identify,
        .applies_at_or_above = .essential,
        .required_evidence = &.{.risk_assessment},
    },
    .{
        .id = "E26-PR-1",
        .domain = .protect,
        .applies_at_or_above = .essential,
        .required_evidence = &.{ .access_control_policy, .network_segmentation_record },
    },
    .{
        .id = "E26-PR-2",
        .domain = .protect,
        .applies_at_or_above = .critical,
        .required_evidence = &.{ .access_control_policy, .network_segmentation_record, .backup_record },
    },
    .{
        .id = "E26-DE-1",
        .domain = .detect,
        .applies_at_or_above = .essential,
        .required_evidence = &.{.monitoring_log},
    },
    .{
        .id = "E26-RS-1",
        .domain = .respond,
        .applies_at_or_above = .essential,
        .required_evidence = &.{.incident_response_plan},
    },
    .{
        .id = "E26-RC-1",
        .domain = .recover,
        .applies_at_or_above = .essential,
        .required_evidence = &.{.backup_record},
    },
    .{
        .id = "E26-AUD-1",
        .domain = .identify,
        .applies_at_or_above = .essential,
        .required_evidence = &.{.periodic_audit_report},
    },
};

fn controlApplies(c: Control, crit: Criticality) bool {
    return @intFromEnum(crit) >= @intFromEnum(c.applies_at_or_above);
}

fn containsEvidence(haystack: []const EvidenceKind, needle: EvidenceKind) bool {
    for (haystack) |e| {
        if (e == needle) return true;
    }
    return false;
}

/// Evaluate one CBS against a control set. Caller supplies a
/// pre-allocated buffer for the verdict array and a buffer for any
/// missing-evidence collection (allocator-free).
pub fn evaluateCBS(
    cbs: ComputerBasedSystem,
    controls: []const Control,
    verdicts_out: []ControlVerdict,
    missing_buf: []EvidenceKind,
) Error!CBSReport {
    if (cbs.evidence.len == 0 and !containsEvidence(cbs.evidence, .asset_register_entry)) {
        // Not strictly empty if we allow systems with zero recorded evidence;
        // the asset_register_entry control will simply fail. No early error.
    }
    if (verdicts_out.len < controls.len) return Error.UnknownEvidence;

    var verdict_count: usize = 0;
    var missing_offset: usize = 0;
    var overall_pass: bool = true;

    for (controls) |c| {
        if (!controlApplies(c, cbs.criticality)) continue;

        const slice_start = missing_offset;
        for (c.required_evidence) |req| {
            if (!containsEvidence(cbs.evidence, req)) {
                if (missing_offset >= missing_buf.len) return Error.UnknownEvidence;
                missing_buf[missing_offset] = req;
                missing_offset += 1;
            }
        }
        const slice_end = missing_offset;
        const missing_slice = missing_buf[slice_start..slice_end];

        const pass = missing_slice.len == 0;
        if (!pass) overall_pass = false;
        verdicts_out[verdict_count] = .{ .control_id = c.id, .pass = pass, .missing = missing_slice };
        verdict_count += 1;
    }

    return .{
        .cbs_id = cbs.id,
        .verdicts = verdicts_out[0..verdict_count],
        .overall_pass = overall_pass,
    };
}

const expectEqual = std.testing.expectEqual;

test "non-essential CBS with asset register entry passes" {
    const evidence = [_]EvidenceKind{.asset_register_entry};
    const cbs: ComputerBasedSystem = .{
        .id = "CBS-001",
        .name = "Cargo handling display",
        .criticality = .non_essential,
        .evidence = &evidence,
    };
    var verdicts: [8]ControlVerdict = undefined;
    var missing: [16]EvidenceKind = undefined;
    const r = try evaluateCBS(cbs, &default_controls, &verdicts, &missing);
    try expectEqual(true, r.overall_pass);
    try expectEqual(@as(usize, 1), r.verdicts.len);
}

test "essential CBS missing risk assessment fails on E26-ID-2" {
    const evidence = [_]EvidenceKind{
        .asset_register_entry, .access_control_policy, .network_segmentation_record,
        .monitoring_log, .incident_response_plan, .backup_record, .periodic_audit_report,
    };
    const cbs: ComputerBasedSystem = .{
        .id = "CBS-002",
        .name = "ECDIS",
        .criticality = .essential,
        .evidence = &evidence,
    };
    var verdicts: [8]ControlVerdict = undefined;
    var missing: [16]EvidenceKind = undefined;
    const r = try evaluateCBS(cbs, &default_controls, &verdicts, &missing);
    try expectEqual(false, r.overall_pass);

    var found_id2: bool = false;
    for (r.verdicts) |v| {
        if (std.mem.eql(u8, v.control_id, "E26-ID-2")) {
            try expectEqual(false, v.pass);
            try expectEqual(@as(usize, 1), v.missing.len);
            try expectEqual(EvidenceKind.risk_assessment, v.missing[0]);
            found_id2 = true;
        }
    }
    try std.testing.expect(found_id2);
}

test "essential CBS with all required evidence passes" {
    const evidence = [_]EvidenceKind{
        .asset_register_entry, .risk_assessment, .access_control_policy,
        .network_segmentation_record, .monitoring_log, .incident_response_plan,
        .backup_record, .periodic_audit_report,
    };
    const cbs: ComputerBasedSystem = .{
        .id = "CBS-003",
        .name = "Bridge nav",
        .criticality = .essential,
        .evidence = &evidence,
    };
    var verdicts: [8]ControlVerdict = undefined;
    var missing: [16]EvidenceKind = undefined;
    const r = try evaluateCBS(cbs, &default_controls, &verdicts, &missing);
    try expectEqual(true, r.overall_pass);
}

test "critical CBS triggers additional E26-PR-2 control" {
    const evidence = [_]EvidenceKind{
        .asset_register_entry, .risk_assessment, .access_control_policy,
        .network_segmentation_record, .monitoring_log, .incident_response_plan,
        .backup_record, .periodic_audit_report,
    };
    const cbs: ComputerBasedSystem = .{
        .id = "CBS-004",
        .name = "Propulsion control",
        .criticality = .critical,
        .evidence = &evidence,
    };
    var verdicts: [8]ControlVerdict = undefined;
    var missing: [16]EvidenceKind = undefined;
    const r = try evaluateCBS(cbs, &default_controls, &verdicts, &missing);
    try expectEqual(true, r.overall_pass);
    // All 8 controls apply for critical (non_essential 1 + essential 6 + critical 1).
    try expectEqual(@as(usize, 8), r.verdicts.len);
}

test "non-essential CBS only sees the asset-register-entry control" {
    const evidence = [_]EvidenceKind{.asset_register_entry};
    const cbs: ComputerBasedSystem = .{
        .id = "CBS-005",
        .name = "Cabin entertainment",
        .criticality = .non_essential,
        .evidence = &evidence,
    };
    var verdicts: [8]ControlVerdict = undefined;
    var missing: [16]EvidenceKind = undefined;
    const r = try evaluateCBS(cbs, &default_controls, &verdicts, &missing);
    try expectEqual(@as(usize, 1), r.verdicts.len);
    try std.testing.expectEqualStrings("E26-ID-1", r.verdicts[0].control_id);
    try expectEqual(true, r.verdicts[0].pass);
}

test "critical CBS missing backup fails on E26-PR-2 and E26-RC-1" {
    const evidence = [_]EvidenceKind{
        .asset_register_entry, .risk_assessment, .access_control_policy,
        .network_segmentation_record, .monitoring_log, .incident_response_plan,
        .periodic_audit_report,
        // backup_record missing
    };
    const cbs: ComputerBasedSystem = .{
        .id = "CBS-006",
        .name = "Propulsion control without backup",
        .criticality = .critical,
        .evidence = &evidence,
    };
    var verdicts: [8]ControlVerdict = undefined;
    var missing: [16]EvidenceKind = undefined;
    const r = try evaluateCBS(cbs, &default_controls, &verdicts, &missing);
    try expectEqual(false, r.overall_pass);
    var fail_count: usize = 0;
    for (r.verdicts) |v| {
        if (!v.pass) fail_count += 1;
    }
    // E26-PR-2 (critical) and E26-RC-1 (essential, applies to critical too)
    // both require backup_record. Both should fail.
    try expectEqual(@as(usize, 2), fail_count);
}

test "evaluateCBS rejects undersized output buffer" {
    const evidence = [_]EvidenceKind{.asset_register_entry};
    const cbs: ComputerBasedSystem = .{
        .id = "CBS-x",
        .name = "x",
        .criticality = .critical,
        .evidence = &evidence,
    };
    var verdicts: [2]ControlVerdict = undefined; // too small for default_controls.len = 8
    var missing: [16]EvidenceKind = undefined;
    try std.testing.expectError(Error.UnknownEvidence, evaluateCBS(cbs, &default_controls, &verdicts, &missing));
}

test "Criticality comparison ordering" {
    try std.testing.expect(@intFromEnum(Criticality.critical) > @intFromEnum(Criticality.essential));
    try std.testing.expect(@intFromEnum(Criticality.essential) > @intFromEnum(Criticality.non_essential));
}
