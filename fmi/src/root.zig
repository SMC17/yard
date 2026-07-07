// yard-fmi-zig public API.
//
// model_description: FMI 3.0 modelDescription.xml generator. Takes a
//                    typed FMU description (variables, units, defaults)
//                    and emits a valid modelDescription.xml string into
//                    a caller-supplied writer.

pub const model_description = @import("model_description.zig");

test {
    _ = model_description;
}
