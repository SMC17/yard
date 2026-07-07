// yard-combat-zig public API.
//
// rcs:      Radar cross-section primitives. Free-space radar range
//           equation: R_max = ((P_t G^2 lambda^2 sigma) / ((4 pi)^3
//           P_min))^(1/4). Per-aspect RCS for a flat plate
//           sigma = 4 pi A^2 / lambda^2 normal incidence; for sphere
//           sigma_geom = pi r^2 (large kr).
//
// weapon:   Weapon-launch reaction. For a horizontal-fire gun:
//           F_recoil = m_proj V_muzzle / dt_charge. For a missile
//           VLS canister: thrust-on-deck during boost; deck-bearing
//           pressure during the firing transient.
//
// magazine: Magazine safety distance per MIL-STD-882 and the
//           NATO STANAG 4439 quantity-distance principle:
//             K_distance = K_factor * NEW^(1/3)
//           with K depending on the building category (inhabited
//           building, public traffic route, etc.).

pub const rcs = @import("rcs.zig");
pub const weapon = @import("weapon.zig");
pub const magazine = @import("magazine.zig");

test {
    _ = rcs;
    _ = weapon;
    _ = magazine;
}
