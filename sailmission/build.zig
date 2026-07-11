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
    const era_mod = b.addModule("yard_era", .{
        .root_source_file = b.path("../era/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sailaero_mod = b.addModule("yard_sailaero", .{
        .root_source_file = b.path("../sailaero/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const econ_mod = b.addModule("yard_econ", .{
        .root_source_file = b.path("../econ/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Fleet targets (arena protocol + mercury evaluator) exist only in the
    // in-flight fleet worktree until arena lands; clean checkouts skip them
    // so CI always builds. Override with -Dfleet if needed.
    const fleet_default = if (b.build_root.handle.access(b.graph.io, "../arena/src/root.zig", .{})) true else |_| false;
    const fleet = b.option(bool, "fleet", "Build fleet (arena/mercury) targets") orelse fleet_default;
    const seastate_mod = b.addModule("yard_seastate", .{
        .root_source_file = b.path("../seastate/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const weathercrit_mod = b.addModule("yard_weathercrit", .{
        .root_source_file = b.path("../weathercrit/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
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

    const mod = b.addModule("yard_sailmission", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_naval_arch", .module = naval_arch_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_routing", .module = routing_mod },
            .{ .name = "yard_era", .module = era_mod },
            .{ .name = "yard_sailaero", .module = sailaero_mod },
            .{ .name = "yard_box_barge", .module = box_barge_mod },
            .{ .name = "yard_econ", .module = econ_mod },
            .{ .name = "yard_weathercrit", .module = weathercrit_mod },
            .{ .name = "yard_seastate", .module = seastate_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "yard-sail-mission",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yard_sailmission", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    if (fleet) {
        const arena_mod = b.addModule("yard_arena", .{
            .root_source_file = b.path("../arena/src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("yard_arena", arena_mod);

        const mercury_exe = b.addExecutable(.{
            .name = "yard-mercury",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/mercury_cli.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "yard_sailmission", .module = mod },
                },
            }),
        });
        b.installArtifact(mercury_exe);

        const mercury_cmd = b.addRunArtifact(mercury_exe);
        if (b.args) |args| mercury_cmd.addArgs(args);
        const mercury_step = b.step("mercury", "Run the Mercury official fleet evaluator");
        mercury_step.dependOn(&mercury_cmd.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run yard-sail-mission");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run sailmission unit tests");
    test_step.dependOn(&run_mod_tests.step);
}
