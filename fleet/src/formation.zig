//! Hierarchical, safety-oriented formation guidance over Yard's linearized
//! Fossen 6-DOF integrator.

const std = @import("std");
const fossen = @import("yard_fossen").fossen;
const design = @import("design.zig");

pub const Vec2 = struct {
    x: f64,
    y: f64,
};

pub const HierarchyLevel = enum(u8) {
    fleet = 0,
    flotilla = 1,
    squadron = 2,
    division = 3,
    vessel = 4,
};

pub const Slot = struct {
    parent_index: ?usize,
    level: HierarchyLevel,
    forward_offset_m: f64 = 0.0,
    port_offset_m: f64 = 0.0,
};

pub const Vessel = struct {
    id: []const u8,
    archetype: design.Archetype,
    state: fossen.State,
    parameters: fossen.Parameters,
    max_speed_m_s: f64,
    max_acceleration_m_s2: f64,

    pub fn fromDesign(id: []const u8, archetype: design.Archetype, derived: design.Derived, state: fossen.State) Vessel {
        return .{
            .id = id,
            .archetype = archetype,
            .state = state,
            .parameters = derived.fossen_parameters,
            .max_speed_m_s = derived.max_speed_m_s,
            .max_acceleration_m_s2 = derived.max_acceleration_m_s2,
        };
    }
};

pub const Mission = struct {
    waypoint_m: Vec2,
    cruise_speed_m_s: f64,
};

pub const Config = struct {
    position_gain_s_inv: f64 = 0.05,
    velocity_gain_s_inv: f64 = 0.25,
    heading_gain_s_inv2: f64 = 0.18,
    yaw_damping_s_inv: f64 = 0.65,
    max_yaw_acceleration_rad_s2: f64 = 0.025,
    avoidance_radius_m: f64 = 250.0,
    minimum_separation_m: f64 = 75.0,
    avoidance_horizon_s: f64 = 90.0,
    avoidance_speed_m_s: f64 = 4.0,
};

pub const Command = struct {
    tau: [6]f64,
    desired_position_m: Vec2,
    desired_velocity_m_s: Vec2,
    desired_heading_rad: f64,
    safety_intervention: bool,
};

pub const Error = error{
    EmptyFleet,
    SizeMismatch,
    EmptyId,
    MultipleRoots,
    RootNotFirst,
    InvalidParent,
    InvalidHierarchy,
    InvalidMission,
    InvalidConfig,
    InvalidTimeStep,
};

fn finiteVec(value: Vec2) bool {
    return std.math.isFinite(value.x) and std.math.isFinite(value.y);
}

fn validate(vessels: []const Vessel, slots: []const Slot, mission: Mission, config: Config) Error!void {
    if (vessels.len == 0) return Error.EmptyFleet;
    if (vessels.len != slots.len) return Error.SizeMismatch;
    if (!finiteVec(mission.waypoint_m) or !std.math.isFinite(mission.cruise_speed_m_s) or mission.cruise_speed_m_s < 0.0) {
        return Error.InvalidMission;
    }
    if (!std.math.isFinite(config.position_gain_s_inv) or config.position_gain_s_inv <= 0.0 or
        !std.math.isFinite(config.velocity_gain_s_inv) or config.velocity_gain_s_inv <= 0.0 or
        !std.math.isFinite(config.heading_gain_s_inv2) or config.heading_gain_s_inv2 <= 0.0 or
        !std.math.isFinite(config.yaw_damping_s_inv) or config.yaw_damping_s_inv < 0.0 or
        !std.math.isFinite(config.max_yaw_acceleration_rad_s2) or config.max_yaw_acceleration_rad_s2 <= 0.0 or
        !std.math.isFinite(config.avoidance_radius_m) or config.avoidance_radius_m <= 0.0 or
        !std.math.isFinite(config.minimum_separation_m) or config.minimum_separation_m <= 0.0 or
        config.minimum_separation_m >= config.avoidance_radius_m or
        !std.math.isFinite(config.avoidance_horizon_s) or config.avoidance_horizon_s <= 0.0 or
        !std.math.isFinite(config.avoidance_speed_m_s) or config.avoidance_speed_m_s <= 0.0)
    {
        return Error.InvalidConfig;
    }

    var roots: usize = 0;
    for (vessels, slots, 0..) |vessel, slot, index| {
        if (vessel.id.len == 0) return Error.EmptyId;
        if (slot.parent_index) |parent| {
            if (parent >= index) return Error.InvalidParent;
            if (@intFromEnum(slot.level) <= @intFromEnum(slots[parent].level)) return Error.InvalidHierarchy;
        } else {
            roots += 1;
            if (index != 0) return Error.RootNotFirst;
        }
    }
    if (roots != 1) return Error.MultipleRoots;
}

fn length(v: Vec2) f64 {
    return @sqrt(v.x * v.x + v.y * v.y);
}

fn clampMagnitude(v: Vec2, maximum: f64) Vec2 {
    const magnitude = length(v);
    if (magnitude <= maximum or magnitude <= 1e-12) return v;
    const scale = maximum / magnitude;
    return .{ .x = v.x * scale, .y = v.y * scale };
}

fn wrapAngle(angle: f64) f64 {
    var result = angle;
    while (result > std.math.pi) result -= 2.0 * std.math.pi;
    while (result < -std.math.pi) result += 2.0 * std.math.pi;
    return result;
}

fn positionOf(vessel: Vessel) Vec2 {
    return .{ .x = vessel.state.eta[0], .y = vessel.state.eta[1] };
}

fn velocityOf(vessel: Vessel) Vec2 {
    const heading = vessel.state.eta[5];
    const c = @cos(heading);
    const s = @sin(heading);
    return .{
        .x = c * vessel.state.nu[0] - s * vessel.state.nu[1],
        .y = s * vessel.state.nu[0] + c * vessel.state.nu[1],
    };
}

pub fn desiredSlotPosition(vessels: []const Vessel, slots: []const Slot, index: usize) Error!Vec2 {
    if (index >= vessels.len or vessels.len != slots.len) return Error.SizeMismatch;
    const slot = slots[index];
    const parent_index = slot.parent_index orelse return positionOf(vessels[index]);
    if (parent_index >= index) return Error.InvalidParent;
    const parent = vessels[parent_index];
    const heading = parent.state.eta[5];
    const c = @cos(heading);
    const s = @sin(heading);
    return .{
        .x = parent.state.eta[0] + c * slot.forward_offset_m - s * slot.port_offset_m,
        .y = parent.state.eta[1] + s * slot.forward_offset_m + c * slot.port_offset_m,
    };
}

fn avoidanceCorrection(vessels: []const Vessel, self_index: usize, config: Config) struct { velocity: Vec2, active: bool } {
    const self = vessels[self_index];
    const self_position = positionOf(self);
    const self_velocity = velocityOf(self);
    var correction: Vec2 = .{ .x = 0.0, .y = 0.0 };
    var active = false;

    for (vessels, 0..) |other, other_index| {
        if (other_index == self_index) continue;
        const relative_position = Vec2{
            .x = other.state.eta[0] - self_position.x,
            .y = other.state.eta[1] - self_position.y,
        };
        const other_velocity = velocityOf(other);
        const relative_velocity = Vec2{
            .x = other_velocity.x - self_velocity.x,
            .y = other_velocity.y - self_velocity.y,
        };
        const relative_speed_sq = relative_velocity.x * relative_velocity.x +
            relative_velocity.y * relative_velocity.y;
        var tcpa: f64 = 0.0;
        if (relative_speed_sq > 1e-12) {
            tcpa = -(relative_position.x * relative_velocity.x + relative_position.y * relative_velocity.y) /
                relative_speed_sq;
            tcpa = std.math.clamp(tcpa, 0.0, config.avoidance_horizon_s);
        }
        const closest = Vec2{
            .x = relative_position.x + relative_velocity.x * tcpa,
            .y = relative_position.y + relative_velocity.y * tcpa,
        };
        const closest_distance = length(closest);
        const current_distance = length(relative_position);
        if (closest_distance >= config.avoidance_radius_m or
            current_distance > 3.0 * config.avoidance_radius_m)
        {
            continue;
        }

        active = true;
        var away: Vec2 = undefined;
        if (closest_distance > 1e-9) {
            away = .{ .x = -closest.x / closest_distance, .y = -closest.y / closest_distance };
        } else {
            const speed = length(self_velocity);
            if (speed > 1e-9) {
                // Deterministic starboard-biased course alteration in a
                // symmetric head-on prediction.
                away = .{ .x = self_velocity.y / speed, .y = -self_velocity.x / speed };
            } else {
                away = if (self_index < other_index)
                    .{ .x = 0.0, .y = -1.0 }
                else
                    .{ .x = 0.0, .y = 1.0 };
            }
        }
        const urgency = std.math.clamp(
            (config.avoidance_radius_m - closest_distance) /
                (config.avoidance_radius_m - config.minimum_separation_m),
            0.0,
            1.0,
        );
        correction.x += away.x * config.avoidance_speed_m_s * urgency;
        correction.y += away.y * config.avoidance_speed_m_s * urgency;
    }
    return .{ .velocity = correction, .active = active };
}

pub fn computeCommands(
    vessels: []const Vessel,
    slots: []const Slot,
    mission: Mission,
    config: Config,
    commands: []Command,
) Error!void {
    try validate(vessels, slots, mission, config);
    if (commands.len != vessels.len) return Error.SizeMismatch;

    for (vessels, slots, commands, 0..) |vessel, slot, *command, index| {
        const current_position = positionOf(vessel);
        const desired_position = if (slot.parent_index == null)
            mission.waypoint_m
        else
            try desiredSlotPosition(vessels, slots, index);
        const position_error = Vec2{
            .x = desired_position.x - current_position.x,
            .y = desired_position.y - current_position.y,
        };

        var desired_velocity: Vec2 = undefined;
        if (slot.parent_index) |parent_index| {
            const parent_velocity = velocityOf(vessels[parent_index]);
            desired_velocity = .{
                .x = parent_velocity.x + config.position_gain_s_inv * position_error.x,
                .y = parent_velocity.y + config.position_gain_s_inv * position_error.y,
            };
        } else {
            const distance = length(position_error);
            const arrival_speed = @sqrt(2.0 * vessel.max_acceleration_m_s2 * distance);
            const target_speed = @min(@min(mission.cruise_speed_m_s, vessel.max_speed_m_s), arrival_speed);
            desired_velocity = if (distance > 1e-12)
                .{ .x = position_error.x * target_speed / distance, .y = position_error.y * target_speed / distance }
            else
                .{ .x = 0.0, .y = 0.0 };
        }

        const avoidance = avoidanceCorrection(vessels, index, config);
        desired_velocity.x += avoidance.velocity.x;
        desired_velocity.y += avoidance.velocity.y;
        desired_velocity = clampMagnitude(desired_velocity, vessel.max_speed_m_s);

        const heading = vessel.state.eta[5];
        const c = @cos(heading);
        const s = @sin(heading);
        const desired_body_velocity = Vec2{
            .x = c * desired_velocity.x + s * desired_velocity.y,
            .y = -s * desired_velocity.x + c * desired_velocity.y,
        };
        const acceleration_body = Vec2{
            .x = std.math.clamp(
                config.velocity_gain_s_inv * (desired_body_velocity.x - vessel.state.nu[0]),
                -vessel.max_acceleration_m_s2,
                vessel.max_acceleration_m_s2,
            ),
            .y = std.math.clamp(
                config.velocity_gain_s_inv * (desired_body_velocity.y - vessel.state.nu[1]),
                -vessel.max_acceleration_m_s2,
                vessel.max_acceleration_m_s2,
            ),
        };
        const desired_heading = if (length(desired_velocity) > 1e-12)
            std.math.atan2(desired_velocity.y, desired_velocity.x)
        else
            vessel.state.eta[5];
        const heading_error = wrapAngle(desired_heading - vessel.state.eta[5]);
        const yaw_acceleration = std.math.clamp(
            config.heading_gain_s_inv2 * heading_error - config.yaw_damping_s_inv * vessel.state.nu[5],
            -config.max_yaw_acceleration_rad_s2,
            config.max_yaw_acceleration_rad_s2,
        );

        var tau: [6]f64 = .{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
        tau[0] = vessel.parameters.M_diag[0] * acceleration_body.x +
            vessel.parameters.D_lin[0] * vessel.state.nu[0];
        tau[1] = vessel.parameters.M_diag[1] * acceleration_body.y +
            vessel.parameters.D_lin[1] * vessel.state.nu[1];
        tau[5] = vessel.parameters.M_diag[5] * yaw_acceleration +
            vessel.parameters.D_lin[5] * vessel.state.nu[5];
        command.* = .{
            .tau = tau,
            .desired_position_m = desired_position,
            .desired_velocity_m_s = desired_velocity,
            .desired_heading_rad = desired_heading,
            .safety_intervention = avoidance.active,
        };
    }
}

pub fn step(
    vessels: []Vessel,
    slots: []const Slot,
    mission: Mission,
    config: Config,
    commands: []Command,
    dt_s: f64,
) !void {
    if (!std.math.isFinite(dt_s) or dt_s <= 0.0) return Error.InvalidTimeStep;
    try computeCommands(vessels, slots, mission, config, commands);
    for (vessels, commands) |*vessel, command| {
        const before = vessel.state;
        var after = try fossen.rk4Step(before, vessel.parameters, command.tau, dt_s);

        // The base kernel intentionally linearizes eta_dot = nu. Formation
        // guidance supports arbitrary yaw, so replace the horizontal position
        // increment with a midpoint body-to-world transform while retaining
        // its RK4 velocity and heave/roll/pitch integration.
        const midpoint_heading = before.eta[5] + 0.5 * wrapAngle(after.eta[5] - before.eta[5]);
        const c = @cos(midpoint_heading);
        const s = @sin(midpoint_heading);
        const average_surge = 0.5 * (before.nu[0] + after.nu[0]);
        const average_sway = 0.5 * (before.nu[1] + after.nu[1]);
        after.eta[0] = before.eta[0] + dt_s * (c * average_surge - s * average_sway);
        after.eta[1] = before.eta[1] + dt_s * (s * average_surge + c * average_sway);
        vessel.state = after;
    }
}

pub fn formationRmsError(vessels: []const Vessel, slots: []const Slot) Error!f64 {
    if (vessels.len == 0) return Error.EmptyFleet;
    if (vessels.len != slots.len) return Error.SizeMismatch;
    if (vessels.len == 1) return 0.0;
    var sum_sq: f64 = 0.0;
    var count: usize = 0;
    for (slots, 0..) |slot, index| {
        if (slot.parent_index == null) continue;
        const target = try desiredSlotPosition(vessels, slots, index);
        const dx = target.x - vessels[index].state.eta[0];
        const dy = target.y - vessels[index].state.eta[1];
        sum_sq += dx * dx + dy * dy;
        count += 1;
    }
    return @sqrt(sum_sq / @as(f64, @floatFromInt(count)));
}

pub fn minimumSeparation(vessels: []const Vessel) Error!f64 {
    if (vessels.len < 2) return Error.EmptyFleet;
    var minimum = std.math.inf(f64);
    for (vessels, 0..) |vessel, i| {
        for (vessels[i + 1 ..]) |other| {
            const dx = other.state.eta[0] - vessel.state.eta[0];
            const dy = other.state.eta[1] - vessel.state.eta[1];
            minimum = @min(minimum, @sqrt(dx * dx + dy * dy));
        }
    }
    return minimum;
}

fn testSpec(id: []const u8) design.Spec {
    var spec: design.Spec = .{
        .id = id,
        .archetype = .merchant,
        .length_m = 200.0,
        .beam_m = 32.0,
        .draft_m = 11.0,
        .block_coefficient = 0.80,
        .waterplane_coefficient = 0.86,
        .declared_displacement_t = 1.0,
        .service_speed_m_s = 8.0,
        .installed_power_kw = 14_000.0,
        .kg_m = 8.0,
        .transverse_gm_m = 2.0,
        .longitudinal_gm_m = 140.0,
    };
    spec.declared_displacement_t = design.displacementFromGeometryT(spec);
    return spec;
}

fn makeState(x: f64, y: f64, heading: f64, vx: f64, vy: f64) fossen.State {
    return .{
        .eta = .{ x, y, 0.0, 0.0, 0.0, heading },
        .nu = .{ vx, vy, 0.0, 0.0, 0.0, 0.0 },
    };
}

fn makeVessel(id: []const u8, initial: fossen.State) !Vessel {
    const spec = testSpec(id);
    return Vessel.fromDesign(id, spec.archetype, try design.derive(spec), initial);
}

test "hierarchical offsets rotate with each immediate parent" {
    const vessels = [_]Vessel{
        try makeVessel("fleet-lead", makeState(0.0, 0.0, std.math.pi / 2.0, 0.0, 0.0)),
        try makeVessel("division-lead", makeState(0.0, 0.0, 0.0, 0.0, 0.0)),
        try makeVessel("unit", makeState(0.0, 0.0, 0.0, 0.0, 0.0)),
    };
    const slots = [_]Slot{
        .{ .parent_index = null, .level = .fleet },
        .{ .parent_index = 0, .level = .division, .forward_offset_m = -100.0 },
        .{ .parent_index = 1, .level = .vessel, .port_offset_m = 40.0 },
    };
    const division_target = try desiredSlotPosition(&vessels, &slots, 1);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), division_target.x, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, -100.0), division_target.y, 1e-10);
    const unit_target = try desiredSlotPosition(&vessels, &slots, 2);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), unit_target.x, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), unit_target.y, 1e-10);
}

test "hierarchy validation rejects forward parent references" {
    const vessels = [_]Vessel{
        try makeVessel("root", makeState(0, 0, 0, 0, 0)),
        try makeVessel("child", makeState(0, 0, 0, 0, 0)),
    };
    const slots = [_]Slot{
        .{ .parent_index = 1, .level = .fleet },
        .{ .parent_index = null, .level = .vessel },
    };
    var commands: [2]Command = undefined;
    try std.testing.expectError(
        Error.InvalidParent,
        computeCommands(&vessels, &slots, .{ .waypoint_m = .{ .x = 10, .y = 0 }, .cruise_speed_m_s = 1 }, .{}, &commands),
    );
}

test "waypoint guidance advances the root and closes formation error" {
    var vessels = [_]Vessel{
        try makeVessel("root", makeState(0.0, 0.0, 0.0, 0.0, 0.0)),
        try makeVessel("wing", makeState(-350.0, 100.0, 0.0, 0.0, 0.0)),
    };
    const slots = [_]Slot{
        .{ .parent_index = null, .level = .fleet },
        .{ .parent_index = 0, .level = .vessel, .forward_offset_m = -150.0, .port_offset_m = 60.0 },
    };
    const initial_error = try formationRmsError(&vessels, &slots);
    var commands: [2]Command = undefined;
    const mission: Mission = .{ .waypoint_m = .{ .x = 1000.0, .y = 0.0 }, .cruise_speed_m_s = 6.0 };
    var i: usize = 0;
    while (i < 1200) : (i += 1) try step(&vessels, &slots, mission, .{}, &commands, 0.1);
    const final_error = try formationRmsError(&vessels, &slots);
    try std.testing.expect(vessels[0].state.eta[0] > 0.0);
    try std.testing.expect(final_error < initial_error);
}

test "predicted head-on encounter produces opposed starboard interventions" {
    const vessels = [_]Vessel{
        try makeVessel("root", makeState(-100.0, 0.0, 0.0, 3.0, 0.0)),
        try makeVessel("child", makeState(100.0, 0.0, std.math.pi, 3.0, 0.0)),
    };
    const slots = [_]Slot{
        .{ .parent_index = null, .level = .fleet },
        .{ .parent_index = 0, .level = .vessel, .forward_offset_m = 200.0 },
    };
    var commands: [2]Command = undefined;
    try computeCommands(
        &vessels,
        &slots,
        .{ .waypoint_m = .{ .x = 1000.0, .y = 0.0 }, .cruise_speed_m_s = 6.0 },
        .{},
        &commands,
    );
    try std.testing.expect(commands[0].safety_intervention);
    try std.testing.expect(commands[1].safety_intervention);
    try std.testing.expect(commands[0].desired_velocity_m_s.y < 0.0);
    try std.testing.expect(commands[1].desired_velocity_m_s.y > 0.0);
}

test "same initial state produces bit-exact deterministic trajectory" {
    var left = [_]Vessel{
        try makeVessel("root", makeState(0.0, 0.0, 0.0, 0.0, 0.0)),
        try makeVessel("wing", makeState(-200.0, 80.0, 0.0, 0.0, 0.0)),
    };
    var right = left;
    const slots = [_]Slot{
        .{ .parent_index = null, .level = .fleet },
        .{ .parent_index = 0, .level = .vessel, .forward_offset_m = -120.0, .port_offset_m = 50.0 },
    };
    const mission: Mission = .{ .waypoint_m = .{ .x = 600.0, .y = 100.0 }, .cruise_speed_m_s = 5.0 };
    var left_commands: [2]Command = undefined;
    var right_commands: [2]Command = undefined;
    for (0..250) |_| {
        try step(&left, &slots, mission, .{}, &left_commands, 0.1);
        try step(&right, &slots, mission, .{}, &right_commands, 0.1);
    }
    for (left, right) |left_vessel, right_vessel| {
        try std.testing.expectEqual(left_vessel.state.eta, right_vessel.state.eta);
        try std.testing.expectEqual(left_vessel.state.nu, right_vessel.state.nu);
    }
}

test "body surge is rotated into world coordinates at nonzero yaw" {
    var vessels = [_]Vessel{try makeVessel(
        "northbound",
        makeState(0.0, 0.0, std.math.pi / 2.0, 0.0, 0.0),
    )};
    const slots = [_]Slot{.{ .parent_index = null, .level = .fleet }};
    var commands: [1]Command = undefined;
    const mission: Mission = .{
        .waypoint_m = .{ .x = 0.0, .y = 500.0 },
        .cruise_speed_m_s = 4.0,
    };
    for (0..300) |_| try step(&vessels, &slots, mission, .{}, &commands, 0.1);
    try std.testing.expect(vessels[0].state.eta[1] > 0.0);
    try std.testing.expect(@abs(vessels[0].state.eta[0]) < 0.01 * vessels[0].state.eta[1]);
}

test "Fossen restoring channels remain active under formation control" {
    var vessels = [_]Vessel{try makeVessel("root", makeState(0.0, 0.0, 0.0, 0.0, 0.0))};
    vessels[0].state.eta[3] = 0.05;
    const slots = [_]Slot{.{ .parent_index = null, .level = .fleet }};
    var commands: [1]Command = undefined;
    const mission: Mission = .{ .waypoint_m = .{ .x = 0.0, .y = 0.0 }, .cruise_speed_m_s = 0.0 };
    for (0..600) |_| try step(&vessels, &slots, mission, .{}, &commands, 0.05);
    try std.testing.expect(@abs(vessels[0].state.eta[3]) < 0.05);
}
