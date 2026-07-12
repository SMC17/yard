const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const naval_arch_mod = b.addModule("yard_naval_arch", .{
        .root_source_file = b.path("../naval-arch/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const hydro_mod = b.addModule("yard_hydro", .{
        .root_source_file = b.path("../hydro/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const stability_mod = b.addModule("yard_stability", .{
        .root_source_file = b.path("../stability/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const resistance_mod = b.addModule("yard_resistance", .{
        .root_source_file = b.path("../resistance/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const routing_mod = b.addModule("yard_routing", .{
        .root_source_file = b.path("../routing/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Reuse compose's canonical workflows as standalone modules; their only
    // imports are the primitive modules above (no spiral dependency).
    const box_barge_mod = b.addModule("yard_box_barge", .{
        .root_source_file = b.path("../compose/src/box_barge.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_stability", .module = stability_mod },
            .{ .name = "yard_naval_arch", .module = naval_arch_mod },
        },
    });

    const cargo_resistance_mod = b.addModule("yard_cargo_resistance", .{
        .root_source_file = b.path("../compose/src/cargo_resistance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_naval_arch", .module = naval_arch_mod },
        },
    });

    const arena_rng_mod = b.addModule("yard_arena_rng", .{
        .root_source_file = b.path("../arena/src/counter_rng.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("yard_mission", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_naval_arch", .module = naval_arch_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_routing", .module = routing_mod },
            .{ .name = "yard_box_barge", .module = box_barge_mod },
            .{ .name = "yard_cargo_resistance", .module = cargo_resistance_mod },
            .{ .name = "yard_arena_rng", .module = arena_rng_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "yard-mission",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yard_mission", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run yard-mission");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run mission unit tests");
    test_step.dependOn(&run_mod_tests.step);
}
