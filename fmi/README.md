# yard-fmi-zig

Proof level: `unit-tested`

yard-fmi-zig is a Zig 0.16 generator for FMI 3.0 CoSimulation
modelDescription.xml from a typed Description struct.

## What it does

- `model_description.Causality` and `model_description.Variability`
  enums matching the FMI 3.0 spec names.
- `model_description.Float64Variable` typed variable declaration
  (name, value reference, causality, variability, optional unit,
  optional description, optional start value).
- `model_description.Description` typed FMU description with model
  name, instantiation token, optional metadata, and a slice of
  variables.
- `model_description.validate` structural correctness check (no
  duplicate value references, no duplicate names, non-empty
  variable list).
- `model_description.write` serializer that fills an ArrayList(u8)
  with a valid CoSimulation FMU modelDescription.xml.

## What it is not (v0.0.0)

- No FMU ZIP packaging (the .fmu archive itself).
- No C ABI runtime (fmi3DoStep, fmi3GetReal, etc.).
- No Float32, Int8/16/32/64, UInt*, Boolean, String, or Binary
  variable types.
- No structural parameters.
- No clocks.
- No terminals (FMI 3.0 terminalsAndIcons.xml).
- No ModelExchange or ScheduledExecution interface types.
- No event handling.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 10/10 tests passed`.

## Public API

```zig
const yard = @import("yard_fmi");
const md = yard.model_description;

const vars = [_]md.Float64Variable{
    .{ .name = "u", .value_reference = 0, .causality = .input, .variability = .continuous, .unit = "m/s" },
    .{ .name = "y", .value_reference = 1, .causality = .output, .variability = .continuous, .unit = "N" },
};
const desc: md.Description = .{
    .model_name = "ResistanceModel",
    .instantiation_token = "{a-uuid-here}",
    .author = "stax",
    .variables = &vars,
};
var list: std.ArrayList(u8) = .empty;
defer list.deinit(allocator);
try md.write(desc, &list, allocator);
// list.items now holds the modelDescription.xml.
```

## Validation

- Enum `.name()` methods return exactly the FMI 3.0 spec strings
  ("parameter", "calculatedParameter", "input", "output", "local",
  "independent", "constant", "fixed", "tunable", "discrete",
  "continuous"). Spec-correctness is asserted at compile time of the
  test.
- Duplicate value reference and duplicate name detection.
- Write emits a non-empty buffer; contains `fmiVersion="3.0"` and the
  model name; emits `<Float64 name="..."` for each variable; places
  output variables in `<ModelStructure>`; includes start values when
  set; includes `<CoSimulation modelIdentifier="...">`; tags are
  matched.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- Modelica Association (2022), *Functional Mock-up Interface
  Specification 3.0*. Published at fmi-standard.org.
- FMI 3.0 schema reference XML at fmi-standard.org.
- Codex cross-references at
  `~/codex/concepts/f9-fmi-3-osp-cosim-envelope-architecture.md`.

## License

AGPL-3.0-or-later.
