//! Benchmark validation report: Wigley, KCS, KVLCC2, Series 60.

const std = @import("std");
const benchmark = @import("yard_benchmark");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    var stdout_buf: [16384]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    var report = try benchmark.harness.runAll(allocator);
    defer benchmark.harness.freeReport(allocator, &report);

    try w.print("=== Yard Benchmark Validation Harness ===\n\n", .{});
    try w.print("Cases: {d} passed, {d} failed\n\n", .{ report.passed, report.failed });

    for (report.results) |r| {
        const hull = benchmark.hulls.get(r.hull);
        const status = if (r.verdict == .pass) "PASS" else "FAIL";
        try w.print("[{s}] {s} / {s} / {s}\n", .{ status, hull.name, r.case_name, r.metric });
        if (r.tolerance > 0.0) {
            try w.print("       expected={d:.6} actual={d:.6} tol={d:.6}\n", .{
                r.expected, r.actual, r.tolerance,
            });
        } else if (r.expected == 0.0 and r.verdict == .pass) {
            try w.print("       actual={d:.4}\n", .{r.actual});
        }
    }

    try w.print("\nOverall: {s}\n", .{if (report.allPassed()) "ALL PASS" else "FAILURES DETECTED"});
    return if (report.allPassed()) 0 else 1;
}

test "harness smoke" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var report = try benchmark.harness.runAll(arena.allocator());
    defer benchmark.harness.freeReport(arena.allocator(), &report);
    try std.testing.expect(report.passed > 0);
}