//! Fail-closed policy for the public 1778 historical simulator.

const std = @import("std");
const types = @import("types.zig");

pub const ViolationCode = enum {
    wrong_schema,
    year_outside_governed_scope,
    missing_source,
    duplicate_source,
    invalid_source_uri,
    source_reference_unknown,
    duplicate_vessel,
    invalid_numeric_range,
    resource_limit_exceeded,
    missing_required_capability,
    signal_capability_mismatch,
    anachronistic_signal,
    anachronistic_capability,
    unsupported_capability,
    side_missing,
};

pub const Violation = struct {
    code: ViolationCode,
    subject: []const u8,
};

pub const Error = error{TooManyViolations};

pub const max_violations = 128;
pub const max_sources = 64;
pub const max_vessels = 64;
pub const max_capabilities_per_vessel = 32;
pub const max_provenance_ids_per_vessel = 32;
pub const max_steps = 10_000;
pub const max_timestep_seconds = 3_600;
pub const max_guns_per_vessel = 200;
pub const max_crew_per_vessel = 2_000;
pub const max_scalar = 1.0e12;
pub const min_positive_scalar = 1.0e-3;
pub const max_step_interval_seconds = max_steps * max_timestep_seconds;

const Recorder = struct {
    out: []Violation,
    count: usize = 0,
    overflowed: bool = false,

    fn add(self: *Recorder, code: ViolationCode, subject: []const u8) void {
        if (self.count >= self.out.len) {
            self.overflowed = true;
            return;
        }
        self.out[self.count] = .{ .code = code, .subject = subject };
        self.count += 1;
    }

    fn result(self: Recorder) Error![]Violation {
        if (self.overflowed) return Error.TooManyViolations;
        return self.out[0..self.count];
    }
};

pub fn validate(scenario: types.Scenario, out: []Violation) Error![]Violation {
    if (out.len < max_violations) return Error.TooManyViolations;
    var violations = Recorder{ .out = out };

    if (!std.mem.eql(u8, scenario.schema_version, types.schema_id))
        violations.add(.wrong_schema, scenario.schema_version);
    if (scenario.year != 1778)
        violations.add(.year_outside_governed_scope, scenario.scenario_id);
    if (scenario.sources.len == 0)
        violations.add(.missing_source, scenario.scenario_id);

    // Bound all work before entering quadratic duplicate checks or the
    // timestep loop. The CLI also caps source bytes before JSON parsing.
    if (scenario.sources.len > max_sources or
        scenario.vessels.len > max_vessels or
        scenario.max_steps > max_steps or
        scenario.timestep_seconds > max_timestep_seconds)
    {
        violations.add(.resource_limit_exceeded, scenario.scenario_id);
        return violations.result();
    }

    for (scenario.sources, 0..) |source, index| {
        if (source.source_id.len == 0 or source.title.len == 0 or source.license.len == 0)
            violations.add(.missing_source, source.source_id);
        if (!std.mem.startsWith(u8, source.uri, "https://"))
            violations.add(.invalid_source_uri, source.source_id);
        for (scenario.sources[0..index]) |previous| {
            if (std.mem.eql(u8, source.source_id, previous.source_id))
                violations.add(.duplicate_source, source.source_id);
        }
    }

    checkUncertain(scenario, scenario.initial_range_m, "initial_range_m", &violations, .nonnegative);
    checkUncertain(scenario, scenario.environment.wind_speed_mps, "wind_speed_mps", &violations, .nonnegative);
    checkUncertain(scenario, scenario.environment.sea_severity, "sea_severity", &violations, .fraction);
    checkUncertain(scenario, scenario.environment.visibility_fraction, "visibility_fraction", &violations, .fraction);
    if (scenario.timestep_seconds == 0 or scenario.max_steps == 0 or scenario.vessels.len < 2)
        violations.add(.invalid_numeric_range, scenario.scenario_id);

    var sides = [_]bool{ false, false };
    for (scenario.vessels, 0..) |vessel, index| {
        sides[@intFromEnum(vessel.side)] = true;
        if (vessel.vessel_id.len == 0)
            violations.add(.invalid_numeric_range, vessel.vessel_id);
        for (scenario.vessels[0..index]) |previous| {
            if (std.mem.eql(u8, vessel.vessel_id, previous.vessel_id))
                violations.add(.duplicate_vessel, vessel.vessel_id);
        }

        if (vessel.capabilities.len > max_capabilities_per_vessel or
            vessel.provenance_ids.len > max_provenance_ids_per_vessel or
            vessel.gunnery.gun_count > max_guns_per_vessel or
            vessel.crew.complement > max_crew_per_vessel)
        {
            violations.add(.resource_limit_exceeded, vessel.vessel_id);
            continue;
        }

        if (!boundedPositive(vessel.displacement_t) or vessel.crew.complement == 0 or vessel.gunnery.gun_count == 0 or
            vessel.gunnery.shot_rounds == 0 or !boundedPositive(vessel.gunnery.powder_kg) or !boundedPositive(vessel.gunnery.shot_mass_kg) or
            !boundedPositive(vessel.damage_control.hull_integrity_points) or !boundedPositive(vessel.damage_control.flooding_capacity) or
            !fraction(vessel.crew.surrender_morale_threshold) or !fraction(vessel.damage_control.withdrawal_hull_fraction))
            violations.add(.invalid_numeric_range, vessel.vessel_id);

        checkRequiredCapabilities(vessel, &violations);
        for (vessel.capabilities) |capability| {
            if (!allowedIn1778(capability))
                violations.add(if (knownLater(capability)) .anachronistic_capability else .unsupported_capability, @tagName(capability));
        }
        if (!signalMatches(vessel.command.signal, vessel.capabilities))
            violations.add(.signal_capability_mismatch, vessel.vessel_id);
        if (vessel.command.signal == .radio or vessel.command.signal == .data_link)
            violations.add(.anachronistic_signal, @tagName(vessel.command.signal));
        for (vessel.provenance_ids) |source_id| requireSource(scenario, source_id, &violations);

        checkUncertain(scenario, vessel.command.order_delay_seconds, vessel.vessel_id, &violations, .step_interval);
        checkUncertain(scenario, vessel.command.signal_failure_probability, vessel.vessel_id, &violations, .fraction);
        checkUncertain(scenario, vessel.crew.initial_morale, vessel.vessel_id, &violations, .fraction);
        checkUncertain(scenario, vessel.crew.training_fraction, vessel.vessel_id, &violations, .fraction);
        checkUncertain(scenario, vessel.gunnery.powder_per_round_kg, vessel.vessel_id, &violations, .positive);
        checkUncertain(scenario, vessel.gunnery.reload_seconds, vessel.vessel_id, &violations, .positive_step_interval);
        checkUncertain(scenario, vessel.gunnery.effective_range_m, vessel.vessel_id, &violations, .positive);
        checkUncertain(scenario, vessel.gunnery.hit_probability_at_reference, vessel.vessel_id, &violations, .fraction);
        checkUncertain(scenario, vessel.gunnery.damage_points_per_hit, vessel.vessel_id, &violations, .nonnegative);
        checkUncertain(scenario, vessel.gunnery.crew_loss_probability_per_hit, vessel.vessel_id, &violations, .fraction);
        checkUncertain(scenario, vessel.gunnery.fire_probability_per_hit, vessel.vessel_id, &violations, .fraction);
        checkUncertain(scenario, vessel.gunnery.flooding_probability_per_hit, vessel.vessel_id, &violations, .fraction);
        checkUncertain(scenario, vessel.damage_control.fire_suppression_per_step, vessel.vessel_id, &violations, .nonnegative);
        checkUncertain(scenario, vessel.damage_control.pumping_per_step, vessel.vessel_id, &violations, .nonnegative);
    }
    if (!sides[0] or !sides[1]) violations.add(.side_missing, scenario.scenario_id);
    return violations.result();
}

const RangeKind = enum { nonnegative, positive, fraction, step_interval, positive_step_interval };

fn checkUncertain(
    scenario: types.Scenario,
    value: types.UncertainF64,
    subject: []const u8,
    violations: *Recorder,
    kind: RangeKind,
) void {
    const finite = std.math.isFinite(value.minimum) and std.math.isFinite(value.central) and std.math.isFinite(value.maximum);
    var valid = finite and value.minimum <= value.central and value.central <= value.maximum;
    const allowed_maximum: f64 = switch (kind) {
        .fraction => 1,
        .step_interval, .positive_step_interval => max_step_interval_seconds,
        .nonnegative, .positive => max_scalar,
    };
    valid = valid and value.maximum <= allowed_maximum;
    valid = valid and switch (kind) {
        .nonnegative, .fraction, .step_interval => value.minimum >= 0,
        .positive, .positive_step_interval => value.minimum >= min_positive_scalar,
    };
    if (!valid) violations.add(.invalid_numeric_range, subject);
    requireSource(scenario, value.source_id, violations);
}

fn requireSource(scenario: types.Scenario, source_id: []const u8, violations: *Recorder) void {
    for (scenario.sources) |source| {
        if (std.mem.eql(u8, source.source_id, source_id)) return;
    }
    violations.add(.source_reference_unknown, source_id);
}

fn checkRequiredCapabilities(vessel: types.Vessel, violations: *Recorder) void {
    const required = [_]types.Capability{
        .wooden_primary_structure,
        .canvas_sail,
        .sail_propulsion,
        .human_lookout,
        .smoothbore_muzzle_loading_cannon,
        .black_powder,
        .solid_round_shot,
        .manual_pump,
    };
    for (required) |capability| {
        if (!hasCapability(vessel.capabilities, capability))
            violations.add(.missing_required_capability, @tagName(capability));
    }
}

fn signalMatches(signal: types.SignalKind, capabilities: []const types.Capability) bool {
    return switch (signal) {
        .signal_flags => hasCapability(capabilities, .signal_flags),
        .lantern_signals => hasCapability(capabilities, .lantern_signals),
        .speaking_trumpet => hasCapability(capabilities, .speaking_trumpet),
        .radio, .data_link => false,
    };
}

fn hasCapability(capabilities: []const types.Capability, wanted: types.Capability) bool {
    for (capabilities) |capability| if (capability == wanted) return true;
    return false;
}

fn allowedIn1778(capability: types.Capability) bool {
    return switch (capability) {
        .wooden_primary_structure, .canvas_sail, .sail_propulsion, .human_lookout, .signal_flags, .lantern_signals, .speaking_trumpet, .manual_pump, .smoothbore_muzzle_loading_cannon, .black_powder, .solid_round_shot, .iron_fasteners => true,
        else => false,
    };
}

fn knownLater(capability: types.Capability) bool {
    return switch (capability) {
        .steam_propulsion, .iron_primary_structure, .steel_primary_structure, .rifled_breech_loading_cannon, .smokeless_powder, .radio, .radar, .sonar, .electronic_fire_control, .guided_weapon, .satellite_navigation, .turbine, .diesel => true,
        else => false,
    };
}

fn fraction(value: f64) bool {
    return std.math.isFinite(value) and value >= 0 and value <= 1;
}

fn boundedPositive(value: f64) bool {
    return std.math.isFinite(value) and value >= min_positive_scalar and value <= max_scalar;
}
