//! R1/R2 -> R3 composition: formation dynamics to deterministic 3D frame.

const std = @import("std");
const fleet = @import("yard_fleet");
const fossen = @import("yard_fossen").fossen;
const viewer = @import("yard_viz_vulkan");

const vessel_count = 3;

const Result = struct {
    ppm: []u8,
    changed_pixels: usize,
    rms_error_m: f64,
    minimum_separation_m: f64,
    simulation_time_s: f64,
};

pub fn main(init: std.process.Init) !u8 {
    var memory = std.heap.ArenaAllocator.init(init.gpa);
    defer memory.deinit();
    const result = try simulateAndRender(memory.allocator());
    const output_path = "fleet-formation.ppm";
    var output = try std.Io.Dir.cwd().createFile(init.io, output_path, .{});
    defer output.close(init.io);
    var file_buffer: [8192]u8 = undefined;
    var file_writer = output.writer(init.io, &file_buffer);
    try file_writer.interface.writeAll(result.ppm);
    try file_writer.interface.flush();

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(result.ppm, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print(
        "frame={s} sha256={s} vessels={d} time_s={d:.1} changed_pixels={d} rms_error_m={d:.3} min_separation_m={d:.3}\n",
        .{ output_path, &digest_hex, vessel_count, result.simulation_time_s, result.changed_pixels, result.rms_error_m, result.minimum_separation_m },
    );
    try stdout_writer.interface.flush();
    return 0;
}

fn simulateAndRender(allocator: std.mem.Allocator) !Result {
    const base = merchantSpec("lead");
    const derived = try fleet.design.derive(base);
    var vessels = [_]fleet.formation.Vessel{
        fleet.formation.Vessel.fromDesign("lead", .merchant, derived, state(0, 0, 0)),
        fleet.formation.Vessel.fromDesign("port-wing", .merchant, derived, state(-450, 200, 0)),
        fleet.formation.Vessel.fromDesign("starboard-wing", .merchant, derived, state(-450, -200, 0)),
    };
    const slots = [_]fleet.formation.Slot{
        .{ .parent_index = null, .level = .fleet },
        .{ .parent_index = 0, .level = .division, .forward_offset_m = -300, .port_offset_m = 150 },
        .{ .parent_index = 0, .level = .division, .forward_offset_m = -300, .port_offset_m = -150 },
    };
    var commands: [vessel_count]fleet.formation.Command = undefined;
    const dt_s = 0.5;
    const steps = 1200;
    for (0..steps) |_| {
        try fleet.formation.step(
            &vessels,
            &slots,
            .{ .waypoint_m = .{ .x = 5000, .y = 0 }, .cruise_speed_m_s = 5.0 },
            .{},
            &commands,
            dt_s,
        );
    }

    var scene_vessels: [vessel_count]viewer.scene.Vessel = undefined;
    for (vessels, &scene_vessels) |vessel, *rendered| {
        rendered.* = .{
            .id = vessel.id,
            .hull = .{ .kind = "wigley", .length_m = base.length_m, .beam_m = base.beam_m, .draft_m = base.draft_m },
            .pose = .{
                .north_m = vessel.state.eta[0],
                .east_m = vessel.state.eta[1],
                .heave_m = vessel.state.eta[2],
                .roll_rad = vessel.state.eta[3],
                .pitch_rad = vessel.state.eta[4],
                .yaw_rad = vessel.state.eta[5],
            },
        };
    }
    const scene: viewer.scene.Scene = .{
        .title = "Yard hierarchical fleet formation",
        .simulation_time_s = dt_s * steps,
        .vessels = &scene_vessels,
    };
    const width = 640;
    const height = 360;
    const rgba = try viewer.frame.createReferenceRgba(allocator, width, height);
    const ppm = try viewer.frame.renderPpmOnRgba(allocator, scene, rgba, width, height);
    return .{
        .ppm = ppm,
        .changed_pixels = viewer.frame.changedPixelCount(rgba),
        .rms_error_m = try fleet.formation.formationRmsError(&vessels, &slots),
        .minimum_separation_m = try fleet.formation.minimumSeparation(&vessels),
        .simulation_time_s = scene.simulation_time_s,
    };
}

fn merchantSpec(id: []const u8) fleet.design.Spec {
    var spec: fleet.design.Spec = .{
        .id = id,
        .archetype = .merchant,
        .length_m = 120,
        .beam_m = 20,
        .draft_m = 7,
        .block_coefficient = 0.72,
        .waterplane_coefficient = 0.82,
        .declared_displacement_t = 1,
        .service_speed_m_s = 7,
        .installed_power_kw = 7000,
        .kg_m = 5,
        .transverse_gm_m = 1.5,
        .longitudinal_gm_m = 80,
    };
    spec.declared_displacement_t = fleet.design.displacementFromGeometryT(spec);
    return spec;
}

fn state(north_m: f64, east_m: f64, yaw_rad: f64) fossen.State {
    return .{
        .eta = .{ north_m, east_m, 0, 0, 0, yaw_rad },
        .nu = .{ 0, 0, 0, 0, 0, 0 },
    };
}

test "hierarchical formation renders a nonblank deterministic fleet frame" {
    var memory_a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer memory_a.deinit();
    var memory_b = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer memory_b.deinit();
    const first = try simulateAndRender(memory_a.allocator());
    const second = try simulateAndRender(memory_b.allocator());
    try std.testing.expectEqualSlices(u8, first.ppm, second.ppm);
    try std.testing.expect(first.changed_pixels > 1000);
    try std.testing.expect(first.minimum_separation_m > 75);
    try std.testing.expect(first.rms_error_m < 1);
}
