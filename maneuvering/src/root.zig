// yard-maneuvering-zig public API.
//
// nomoto: Nomoto first-order K-T yaw model and second-order T1/T2/T3
//         variant. Step-response analytical solutions and a zig-zag
//         overshoot estimator.

pub const nomoto = @import("nomoto.zig");

test {
    _ = nomoto;
}
