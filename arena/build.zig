const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arena_mod = b.addModule("yard_arena", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = arena_mod });
    const test_step = b.step("test", "Run Yard Arena unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const score_exe = b.addExecutable(.{
        .name = "yard-arena-score",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/score_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "yard_arena", .module = arena_mod }},
        }),
    });
    b.installArtifact(score_exe);

    const run_score = b.addRunArtifact(score_exe);
    if (b.args) |args| run_score.addArgs(args);
    const score_step = b.step("score", "Score a mission submission and trusted simulation result");
    score_step.dependOn(&run_score.step);

    const rng_vector_exe = b.addExecutable(.{
        .name = "yard-arena-rng-vector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/rng_vector_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "yard_arena", .module = arena_mod }},
        }),
    });
    const run_rng_vector = b.addRunArtifact(rng_vector_exe);
    if (b.args) |args| run_rng_vector.addArgs(args);
    const rng_vector_step = b.step("rng-vector", "Emit a blake3-counter-v1 conformance vector");
    rng_vector_step.dependOn(&run_rng_vector.step);

    const replay_exe = b.addExecutable(.{
        .name = "yard-arena-replay",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/replay_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "yard_arena", .module = arena_mod }},
        }),
    });
    b.installArtifact(replay_exe);
    const run_replay = b.addRunArtifact(replay_exe);
    if (b.args) |args| run_replay.addArgs(args);
    const replay_step = b.step("replay", "Verify a replay NDJSON hash chain");
    replay_step.dependOn(&run_replay.step);

    const season_exe = b.addExecutable(.{
        .name = "yard-arena-season",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/season_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "yard_arena", .module = arena_mod }},
        }),
    });
    b.installArtifact(season_exe);
    const run_season = b.addRunArtifact(season_exe);
    if (b.args) |args| run_season.addArgs(args);
    const season_step = b.step("season", "Commit, sign, or verify a hidden-season manifest");
    season_step.dependOn(&run_season.step);
}
