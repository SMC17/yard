const std = @import("std");
const sim = @import("vessel_sim.zig");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    // Verify generated Autonomy Thrust Allocation mathematical correctness
    const tau_test = [3]f64{ 100.0, 50.0, 10.0 };
    const f_alloc = sim.thrustAllocation(tau_test);
    const reconstructed_surge = f_alloc[1] + f_alloc[3];
    const reconstructed_sway = f_alloc[0] + f_alloc[2] + f_alloc[4];

    std.testing.expectApproxEqAbs(tau_test[0], reconstructed_surge, 1e-6) catch return 1;
    std.testing.expectApproxEqAbs(tau_test[1], reconstructed_sway, 1e-6) catch return 1;
    
    // Create the simulation output CSV file
    var csv_file = try std.Io.Dir.cwd().createFile(init.io, "examples/design-spiral-wigley/simulation_output.csv", .{});
    defer csv_file.close(init.io);
    
    var write_buf: [4096]u8 = undefined;
    var writer = csv_file.writer(init.io, &write_buf);
    
    // Run a 5-second simulation to verify correctness and write directly to file
    try sim.runSimulation(allocator, &writer.interface, 5.0, 0.5);
    try writer.interface.flush();
    
    // Print success summary to stdout
    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_w.interface;
    defer stdout.flush() catch {};
    
    try stdout.print("Successfully compiled and executed generated simulator!\n", .{});
    try stdout.print("Saved simulated trajectory to examples/design-spiral-wigley/simulation_output.csv\n", .{});
    return 0;
}
