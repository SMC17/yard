// yard-cathodic-zig public API.
//
// faraday: Faraday law of electrolysis. Anode mass loss in cathodic
//          protection systems for a given current and exposure time:
//            m = (I * t * M) / (n * F)
//          with M the atomic mass [kg/mol], n the valence [-], F the
//          Faraday constant 96 485 C/mol.
//
// design:  DNV-RP-B401 style sacrificial-anode current demand and
//          mass calculation:
//            I_total = A_surface * i_c (mean current density)
//            m_anode = I_total * design_life / capacity * utilisation
//          where capacity is the anode electrochemical capacity
//          (A h / kg).

pub const faraday = @import("faraday.zig");
pub const design = @import("design.zig");

test {
    _ = faraday;
    _ = design;
}
