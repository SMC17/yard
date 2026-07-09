const std = @import("std");

const core_modules = [_][]const u8{
    "hydro",
    "stability",
    "naval-arch",
    "similarity",
    "benchmark",
    "spiral",
    "compose",
    "viz",
};

const all_modules = [_][]const u8{
    "ais",           "anchor",        "auv",           "azipod",
    "bem",           "bow",           "cargo",         "cathodic",
    "cavitation",    "cii",           "collision",     "combat",
    "coupled-motions", "csr",         "csr-buckling",  "csr-fatigue",
    "deck",          "deicing",       "drydock",       "dynpos",
    "eedi",          "engine",        "flettner",      "fmi",
    "foilcraft",     "fossen-6dof",   "fueltank",      "grounding",
    "helideck",      "hess-smith-3d", "hydro",         "icebreaker",
    "irf",           "ittc78",        "jacket",        "keel",
    "similarity",    "benchmark",   "spiral",
    "launch",        "load-line",     "maneuvering",   "mass",
    "mooring",       "naval-arch",    "noise",         "pipeline",
    "port-engineering", "port-logistics", "propulsion", "rao-spectrum",
    "recycling",     "resistance",    "roro",          "routing",
    "saildrone",     "savitsky",      "seakeeping",    "shaft",
    "shipyard-mgmt", "sloshing",      "springing",     "stability",
    "stir",          "strength",      "strip-theory",  "submarine",
    "terminal",      "towing-tank",   "tug",           "vimstab",
    "windaero",
};

fn addModuleTest(b: *std.Build, dir: []const u8, target: std.Build.ResolvedTarget, test_step: *std.Build.Step) void {
    const root_path = b.fmt("{s}/src/root.zig", .{dir});
    const mod = b.addModule(dir, .{
        .root_source_file = b.path(root_path),
        .target = target,
    });
    const tests = b.addTest(.{ .root_module = mod });
    const run = b.addRunArtifact(tests);
    run.has_side_effects = true;
    test_step.dependOn(&run.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_core = b.step("test-core", "Test hydro + stability + naval-arch + compose + viz + examples");

    for (core_modules) |mod| {
        if (!std.mem.eql(u8, mod, "compose") and !std.mem.eql(u8, mod, "viz") and
            !std.mem.eql(u8, mod, "spiral") and !std.mem.eql(u8, mod, "benchmark"))
        {
            addModuleTest(b, mod, target, test_core);
        }
    }

    const viz_mod = b.addModule("yard_viz_core", .{
        .root_source_file = b.path("viz/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const viz_tests = b.addTest(.{ .root_module = viz_mod });
    test_core.dependOn(&b.addRunArtifact(viz_tests).step);

    const hydro_mod = b.addModule("yard_hydro_core", .{
        .root_source_file = b.path("hydro/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const stability_mod = b.addModule("yard_stability_core", .{
        .root_source_file = b.path("stability/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const resistance_mod = b.addModule("yard_resistance_core", .{
        .root_source_file = b.path("resistance/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const naval_mod = b.addModule("yard_naval_arch_core", .{
        .root_source_file = b.path("naval-arch/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const seakeeping_mod = b.addModule("yard_seakeeping_core", .{
        .root_source_file = b.path("seakeeping/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const rao_mod = b.addModule("yard_rao_spectrum_core", .{
        .root_source_file = b.path("rao-spectrum/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fossen_mod = b.addModule("yard_fossen_core", .{
        .root_source_file = b.path("fossen-6dof/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const strip_mod = b.addModule("yard_strip_theory_core", .{
        .root_source_file = b.path("strip-theory/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const similarity_mod = b.addModule("yard_similarity_core", .{
        .root_source_file = b.path("similarity/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ittc78_mod = b.addModule("yard_ittc78_core", .{
        .root_source_file = b.path("ittc78/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const benchmark_mod = b.addModule("yard_benchmark_core", .{
        .root_source_file = b.path("benchmark/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
            .{ .name = "yard_similarity", .module = similarity_mod },
            .{ .name = "yard_ittc78", .module = ittc78_mod },
        },
    });
    const benchmark_tests = b.addTest(.{ .root_module = benchmark_mod });
    test_core.dependOn(&b.addRunArtifact(benchmark_tests).step);

    const spiral_mod = b.addModule("yard_spiral_core", .{
        .root_source_file = b.path("spiral/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_stability", .module = stability_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
            .{ .name = "yard_similarity", .module = similarity_mod },
            .{ .name = "yard_ittc78", .module = ittc78_mod },
            .{ .name = "yard_fossen", .module = fossen_mod },
            .{ .name = "yard_seakeeping", .module = seakeeping_mod },
            .{ .name = "yard_rao_spectrum", .module = rao_mod },
            .{ .name = "yard_strip_theory", .module = strip_mod },
        },
    });
    const spiral_tests = b.addTest(.{ .root_module = spiral_mod });
    test_core.dependOn(&b.addRunArtifact(spiral_tests).step);

    const dynpos_mod = b.addModule("yard_dynpos_core", .{
        .root_source_file = b.path("dynpos/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const compose_mod = b.addModule("yard_compose_core", .{
        .root_source_file = b.path("compose/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_stability", .module = stability_mod },
            .{ .name = "yard_resistance", .module = resistance_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
            .{ .name = "yard_seakeeping", .module = seakeeping_mod },
            .{ .name = "yard_rao_spectrum", .module = rao_mod },
            .{ .name = "yard_fossen", .module = fossen_mod },
            .{ .name = "yard_strip_theory", .module = strip_mod },
            .{ .name = "yard_dynpos", .module = dynpos_mod },
            .{ .name = "yard_viz", .module = viz_mod },
            .{ .name = "yard_spiral", .module = spiral_mod },
        },
    });
    const compose_tests = b.addTest(.{ .root_module = compose_mod });
    test_core.dependOn(&b.addRunArtifact(compose_tests).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/box-barge-intact-stability/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_compose", .module = compose_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
        },
    });
    const example_tests = b.addTest(.{ .root_module = example_mod });
    test_core.dependOn(&b.addRunArtifact(example_tests).step);

    const test_all = b.step("test-all", "Test all 69 primitive modules");
    for (all_modules) |mod| {
        addModuleTest(b, mod, target, test_all);
    }

    const run_example = b.step("run-example", "Run box-barge intact stability example");
    const exe = b.addExecutable(.{
        .name = "box-barge-example",
        .root_module = example_mod,
    });
    const run_cmd = b.addRunArtifact(exe);
    run_example.dependOn(&run_cmd.step);

    const full_assess_mod = b.createModule(.{
        .root_source_file = b.path("examples/full-vessel-assessment/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_compose", .module = compose_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
        },
    });
    const full_assess_tests = b.addTest(.{ .root_module = full_assess_mod });
    test_core.dependOn(&b.addRunArtifact(full_assess_tests).step);

    const run_full = b.step("run-full-assessment", "Run stability + resistance assessment");
    const full_exe = b.addExecutable(.{
        .name = "full-vessel-assessment",
        .root_module = full_assess_mod,
    });
    run_full.dependOn(&b.addRunArtifact(full_exe).step);

    const seakeeping_mod_example = b.createModule(.{
        .root_source_file = b.path("examples/seakeeping_assessment/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_compose", .module = compose_mod },
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
        },
    });
    const seakeeping_tests = b.addTest(.{ .root_module = seakeeping_mod_example });
    test_core.dependOn(&b.addRunArtifact(seakeeping_tests).step);

    const run_seakeeping = b.step("run-seakeeping", "Run seakeeping assessment example");
    const seakeeping_exe = b.addExecutable(.{
        .name = "seakeeping-assessment",
        .root_module = seakeeping_mod_example,
    });
    run_seakeeping.dependOn(&b.addRunArtifact(seakeeping_exe).step);

    const spiral_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/design-spiral-wigley/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_similarity", .module = similarity_mod },
            .{ .name = "yard_compose", .module = compose_mod },
            .{ .name = "yard_spiral", .module = spiral_mod },
            .{ .name = "yard_naval_arch", .module = naval_mod },
        },
    });
    const spiral_demo_tests = b.addTest(.{ .root_module = spiral_demo_mod });
    test_core.dependOn(&b.addRunArtifact(spiral_demo_tests).step);

    const run_spiral = b.step("run-spiral", "Run Evans design spiral Wigley demo");
    const spiral_exe = b.addExecutable(.{
        .name = "design-spiral-wigley",
        .root_module = spiral_demo_mod,
    });
    run_spiral.dependOn(&b.addRunArtifact(spiral_exe).step);

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("examples/benchmark-validation/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_benchmark", .module = benchmark_mod },
        },
    });
    const bench_tests = b.addTest(.{ .root_module = bench_mod });
    test_core.dependOn(&b.addRunArtifact(bench_tests).step);

    const run_benchmark = b.step("run-benchmark", "Run standard-hull validation harness");
    const bench_exe = b.addExecutable(.{
        .name = "benchmark-validation",
        .root_module = bench_mod,
    });
    run_benchmark.dependOn(&b.addRunArtifact(bench_exe).step);

    const sim_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/sim-suite-demo/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_compose", .module = compose_mod },
        },
    });
    const sim_demo_tests = b.addTest(.{ .root_module = sim_demo_mod });
    test_core.dependOn(&b.addRunArtifact(sim_demo_tests).step);

    const run_sim_suite = b.step("run-sim-suite", "Run DP + irregular waves + Pareto demo");
    const sim_exe = b.addExecutable(.{
        .name = "sim-suite-demo",
        .root_module = sim_demo_mod,
    });
    run_sim_suite.dependOn(&b.addRunArtifact(sim_exe).step);
}