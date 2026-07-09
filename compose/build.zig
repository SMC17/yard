const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const naval_arch_mod = b.addModule("yard_naval_arch", .{
        .root_source_file = b.path("../naval-arch/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const seakeeping_mod = b.addModule("yard_seakeeping", .{
        .root_source_file = b.path("../seakeeping/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const rao_mod = b.addModule("yard_rao_spectrum", .{
        .root_source_file = b.path("../rao-spectrum/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fossen_mod = b.addModule("yard_fossen", .{
        .root_source_file = b.path("../fossen-6dof/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const strip_mod = b.addModule("yard_strip_theory", .{
        .root_source_file = b.path("../strip-theory/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const similarity_mod = b.addModule("yard_similarity", .{
        .root_source_file = b.path("../similarity/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ittc78_mod = b.addModule("yard_ittc78", .{
        .root_source_file = b.path("../ittc78/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dynpos_mod = b.addModule("yard_dynpos", .{
        .root_source_file = b.path("../dynpos/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const viz_mod = b.addModule("yard_viz", .{
        .root_source_file = b.path("../viz/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const spiral_mod = b.addModule("yard_spiral", .{
        .root_source_file = b.path("../spiral/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_stability", .module = stability_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_naval_arch", .module = naval_arch_mod },
            .{ .name = "yard_similarity", .module = similarity_mod },
            .{ .name = "yard_ittc78", .module = ittc78_mod },
            .{ .name = "yard_fossen", .module = fossen_mod },
            .{ .name = "yard_seakeeping", .module = seakeeping_mod },
            .{ .name = "yard_rao_spectrum", .module = rao_mod },
            .{ .name = "yard_strip_theory", .module = strip_mod },
        },
    });

    const mod = b.addModule("yard_compose", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_stability", .module = stability_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_naval_arch", .module = naval_arch_mod },
            .{ .name = "yard_seakeeping", .module = seakeeping_mod },
            .{ .name = "yard_rao_spectrum", .module = rao_mod },
            .{ .name = "yard_fossen", .module = fossen_mod },
            .{ .name = "yard_strip_theory", .module = strip_mod },
            .{ .name = "yard_dynpos", .module = dynpos_mod },
            .{ .name = "yard_viz", .module = viz_mod },
            .{ .name = "yard_spiral", .module = spiral_mod },
        },
    });

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run compose unit tests");
    test_step.dependOn(&run_mod_tests.step);
}