const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hydro_mod = b.addModule("yard_hydro", .{
        .root_source_file = b.path("../hydro/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const resistance_mod = b.addModule("yard_resistance", .{
        .root_source_file = b.path("../resistance/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const naval_mod = b.addModule("yard_naval_arch", .{
        .root_source_file = b.path("../naval-arch/src/root.zig"),
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
    const towing_tank_mod = b.addModule("yard_towing_tank", .{
        .root_source_file = b.path("../towing-tank/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("yard_benchmark", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
            .{ .name = "yard_similarity", .module = similarity_mod },
            .{ .name = "yard_ittc78", .module = ittc78_mod },
            .{ .name = "yard_towing_tank", .module = towing_tank_mod },
        },
    });

    const mod_tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run benchmark validation tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
}