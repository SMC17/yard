// FMI 3.0 modelDescription.xml generator.
//
// FMI 3.0 was released by the Modelica Association in 2022. The
// modelDescription.xml is the metadata file at the root of every FMU
// archive; it declares the model's variables, their types, causality
// (parameter, input, output, local), variability (constant, fixed,
// tunable, discrete, continuous), and value references.
//
// This v0.0.0 generator emits a minimal-but-valid CoSimulation FMU
// modelDescription.xml for a model with Float64 variables only.
// Inputs come in as a typed struct; the output goes to any writer.
//
// Scope of v0.0.0:
//   - FMI 3.0, FmiVersion = "3.0"
//   - CoSimulation interface type only
//   - Float64 variables only
//   - Variables: name, value reference, causality, variability,
//     start value (optional), description (optional), unit (optional)
//   - No structural parameters, no clocks, no terminals, no events.

const std = @import("std");

pub const Causality = enum {
    parameter,
    calculated_parameter,
    input,
    output,
    local,
    independent,

    pub fn name(self: Causality) []const u8 {
        return switch (self) {
            .parameter => "parameter",
            .calculated_parameter => "calculatedParameter",
            .input => "input",
            .output => "output",
            .local => "local",
            .independent => "independent",
        };
    }
};

pub const Variability = enum {
    constant,
    fixed,
    tunable,
    discrete,
    continuous,

    pub fn name(self: Variability) []const u8 {
        return @tagName(self);
    }
};

pub const Float64Variable = struct {
    name: []const u8,
    value_reference: u32,
    causality: Causality,
    variability: Variability,
    description: ?[]const u8 = null,
    unit: ?[]const u8 = null,
    start: ?f64 = null,
};

pub const Description = struct {
    model_name: []const u8,
    instantiation_token: []const u8,
    description: ?[]const u8 = null,
    author: ?[]const u8 = null,
    version: ?[]const u8 = null,
    generation_tool: ?[]const u8 = "yard-fmi-zig",
    variables: []const Float64Variable,
};

pub const Error = error{
    EmptyVariables,
    DuplicateValueReference,
    DuplicateName,
    OutOfMemory,
};

/// Validate the description for structural correctness without writing.
pub fn validate(d: Description) Error!void {
    if (d.variables.len == 0) return Error.EmptyVariables;
    for (d.variables, 0..) |v, i| {
        for (d.variables[i + 1 ..]) |w| {
            if (v.value_reference == w.value_reference) return Error.DuplicateValueReference;
            if (std.mem.eql(u8, v.name, w.name)) return Error.DuplicateName;
        }
    }
}

fn appendFmt(
    list: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) Error!void {
    const s = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(s);
    try list.appendSlice(gpa, s);
}

fn appendStr(list: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) Error!void {
    try list.appendSlice(gpa, s);
}

/// Write the modelDescription.xml to the provided ArrayList(u8). Caller
/// owns the buffer.
pub fn write(d: Description, list: *std.ArrayList(u8), gpa: std.mem.Allocator) Error!void {
    try validate(d);

    try appendStr(list, gpa, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try appendFmt(list, gpa,
        "<fmiModelDescription fmiVersion=\"3.0\" modelName=\"{s}\" instantiationToken=\"{s}\"",
        .{ d.model_name, d.instantiation_token },
    );
    if (d.description) |desc| try appendFmt(list, gpa, " description=\"{s}\"", .{desc});
    if (d.author) |a| try appendFmt(list, gpa, " author=\"{s}\"", .{a});
    if (d.version) |v| try appendFmt(list, gpa, " version=\"{s}\"", .{v});
    if (d.generation_tool) |g| try appendFmt(list, gpa, " generationTool=\"{s}\"", .{g});
    try appendStr(list, gpa, ">\n");

    // CoSimulation interface declaration.
    try appendFmt(list, gpa, "  <CoSimulation modelIdentifier=\"{s}\"/>\n", .{d.model_name});

    // ModelVariables.
    try appendStr(list, gpa, "  <ModelVariables>\n");
    for (d.variables) |v| {
        try appendFmt(list, gpa,
            "    <Float64 name=\"{s}\" valueReference=\"{d}\" causality=\"{s}\" variability=\"{s}\"",
            .{ v.name, v.value_reference, v.causality.name(), v.variability.name() },
        );
        if (v.description) |desc| try appendFmt(list, gpa, " description=\"{s}\"", .{desc});
        if (v.unit) |u| try appendFmt(list, gpa, " unit=\"{s}\"", .{u});
        if (v.start) |s| try appendFmt(list, gpa, " start=\"{d}\"", .{s});
        try appendStr(list, gpa, "/>\n");
    }
    try appendStr(list, gpa, "  </ModelVariables>\n");

    // ModelStructure: each output variable becomes an <Output valueReference="..."/>.
    try appendStr(list, gpa, "  <ModelStructure>\n");
    for (d.variables) |v| {
        if (v.causality == .output) {
            try appendFmt(list, gpa, "    <Output valueReference=\"{d}\"/>\n", .{v.value_reference});
        }
    }
    try appendStr(list, gpa, "  </ModelStructure>\n");

    try appendStr(list, gpa, "</fmiModelDescription>\n");
}

const expectEqual = std.testing.expectEqual;

test "Causality and Variability names match FMI 3.0 spec" {
    try std.testing.expectEqualStrings("parameter", Causality.parameter.name());
    try std.testing.expectEqualStrings("calculatedParameter", Causality.calculated_parameter.name());
    try std.testing.expectEqualStrings("input", Causality.input.name());
    try std.testing.expectEqualStrings("output", Causality.output.name());
    try std.testing.expectEqualStrings("local", Causality.local.name());
    try std.testing.expectEqualStrings("independent", Causality.independent.name());
    try std.testing.expectEqualStrings("constant", Variability.constant.name());
    try std.testing.expectEqualStrings("fixed", Variability.fixed.name());
    try std.testing.expectEqualStrings("tunable", Variability.tunable.name());
    try std.testing.expectEqualStrings("discrete", Variability.discrete.name());
    try std.testing.expectEqualStrings("continuous", Variability.continuous.name());
}

test "validate rejects empty variables list" {
    const d: Description = .{
        .model_name = "Test",
        .instantiation_token = "{token}",
        .variables = &.{},
    };
    try std.testing.expectError(Error.EmptyVariables, validate(d));
}

test "validate rejects duplicate value references" {
    const vars = [_]Float64Variable{
        .{ .name = "a", .value_reference = 1, .causality = .parameter, .variability = .fixed },
        .{ .name = "b", .value_reference = 1, .causality = .input, .variability = .continuous },
    };
    const d: Description = .{
        .model_name = "Test",
        .instantiation_token = "{token}",
        .variables = &vars,
    };
    try std.testing.expectError(Error.DuplicateValueReference, validate(d));
}

test "validate rejects duplicate names" {
    const vars = [_]Float64Variable{
        .{ .name = "a", .value_reference = 1, .causality = .parameter, .variability = .fixed },
        .{ .name = "a", .value_reference = 2, .causality = .input, .variability = .continuous },
    };
    const d: Description = .{
        .model_name = "Test",
        .instantiation_token = "{token}",
        .variables = &vars,
    };
    try std.testing.expectError(Error.DuplicateName, validate(d));
}

test "write produces a non-empty XML for a single-variable model" {
    const vars = [_]Float64Variable{
        .{ .name = "x", .value_reference = 0, .causality = .input, .variability = .continuous, .unit = "m" },
    };
    const d: Description = .{
        .model_name = "Mini",
        .instantiation_token = "{abc}",
        .variables = &vars,
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try write(d, &list, std.testing.allocator);
    try std.testing.expect(list.items.len > 100);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "fmiVersion=\"3.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "modelName=\"Mini\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<Float64 name=\"x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "unit=\"m\"") != null);
}

test "write places output variable in ModelStructure" {
    const vars = [_]Float64Variable{
        .{ .name = "u", .value_reference = 0, .causality = .input, .variability = .continuous },
        .{ .name = "y", .value_reference = 1, .causality = .output, .variability = .continuous },
    };
    const d: Description = .{
        .model_name = "IO",
        .instantiation_token = "{io}",
        .variables = &vars,
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try write(d, &list, std.testing.allocator);
    // ModelStructure should contain <Output valueReference="1"/>.
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<Output valueReference=\"1\"/>") != null);
}

test "write emits start value when set" {
    const vars = [_]Float64Variable{
        .{ .name = "x0", .value_reference = 0, .causality = .parameter, .variability = .fixed, .start = 3.14 },
    };
    const d: Description = .{
        .model_name = "P",
        .instantiation_token = "{p}",
        .variables = &vars,
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try write(d, &list, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "start=\"3.14\"") != null);
}

test "write includes CoSimulation interface declaration" {
    const vars = [_]Float64Variable{
        .{ .name = "x", .value_reference = 0, .causality = .input, .variability = .continuous },
    };
    const d: Description = .{
        .model_name = "X",
        .instantiation_token = "{x}",
        .variables = &vars,
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try write(d, &list, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<CoSimulation modelIdentifier=\"X\"") != null);
}

test "write XML is well-formed (matched tags)" {
    const vars = [_]Float64Variable{
        .{ .name = "x", .value_reference = 0, .causality = .input, .variability = .continuous },
        .{ .name = "y", .value_reference = 1, .causality = .output, .variability = .continuous },
    };
    const d: Description = .{
        .model_name = "Test",
        .instantiation_token = "{t}",
        .variables = &vars,
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try write(d, &list, std.testing.allocator);
    // Root open/close.
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<fmiModelDescription") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "</fmiModelDescription>") != null);
    // ModelVariables open/close.
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<ModelVariables>") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "</ModelVariables>") != null);
    // ModelStructure open/close.
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<ModelStructure>") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "</ModelStructure>") != null);
}
