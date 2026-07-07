// yard-auv-zig public API.
//
// hydrodynamics: Low-Reynolds drag (intermediate-Re regime relevant
//                for AUVs around 1-5 m/s). Drag coefficient from
//                ITTC-57 friction + form factor + appendage allowance;
//                useful for endurance models.
//
// depth_control: PD depth-keeping autopilot: depth-error -> stern
//                plane deflection. The control surface generates a
//                pitching moment which (after a transient) produces a
//                steady-state vertical velocity matching commanded
//                depth.
//
// endurance:     Battery + propulsion energy budget. E_total =
//                P_propulsion * t / eta_propulsive + P_hotel * t.
//                Range = V * t.
//
// glider:        Sea-glider polar: net buoyancy delta_B converts to
//                a forward velocity through a glide angle alpha and
//                a fixed lift-to-drag ratio L/D.

pub const hydrodynamics = @import("hydrodynamics.zig");
pub const depth_control = @import("depth_control.zig");
pub const endurance = @import("endurance.zig");
pub const glider = @import("glider.zig");

test {
    _ = hydrodynamics;
    _ = depth_control;
    _ = endurance;
    _ = glider;
}
