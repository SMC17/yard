// yard-mooring-zig public API.
//
// catenary: Inextensible static catenary cable suspended between an
//           anchor on the seabed and a fairlead. Closed-form catenary
//           equations relating horizontal force H, weight per unit
//           length w, fairlead horizontal offset x, and fairlead
//           vertical offset y. Tension magnitude, arc length, and
//           anchor-touchdown calculation.

pub const catenary = @import("catenary.zig");

test {
    _ = catenary;
}
