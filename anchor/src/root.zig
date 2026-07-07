// yard-anchor-zig public API.
//
// holding: Anchor holding power per the IACS A1 Stevin / SHHP family.
//          For a Stevin-style high-holding-power anchor in firm
//          seabed:
//            H_max ~ K * W^(0.92)  [kN, with W in kN]
//          with K = 1.0 (standard), 1.3 (HHP), 1.7 (SHHP). Add the
//          on-bottom chain weight to recover the total horizontal
//          holding force.
//
// scope: Scope-length-vs-water-depth geometry. To keep the anchor
//        shank horizontal at the seabed (the design assumption for
//        Stevin holding-power tests), the chain must lie flat for a
//        minimum length L_floor on the seabed. The total cable length
//        out is L_total = L_floor + L_catenary(H, w, depth).

pub const holding = @import("holding.zig");
pub const scope = @import("scope.zig");

test {
    _ = holding;
    _ = scope;
}
