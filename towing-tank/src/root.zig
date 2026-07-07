// yard-towing-tank-zig public API.
//
// prohaska: Prohaska plot for the form factor (1+k) extracted from
//           low-Froude-number tank resistance data.
//           C_T / C_F = (1 + k) + a Fn^4 / C_F per ITTC 7.5-02-02-01.
//           Linear least-squares fit on the transformed pair
//           (X, Y) = (Fn^4 / C_F, C_T / C_F).
//
// self_prop: Self-propulsion thrust-deduction t and wake-fraction w
//            extraction from model self-propulsion tests using the
//            ITTC linear formulation:
//              R_T_model = T (1 - t)   (force balance at SOP)
//              V_a = V_m (1 - w_T)     (advance velocity)

pub const prohaska = @import("prohaska.zig");
pub const self_prop = @import("self_prop.zig");

test {
    _ = prohaska;
    _ = self_prop;
}
