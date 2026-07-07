// yard-vimstab-zig public API.
//
// container_stack: IMO MSC.252(83) container-stack lateral-load
//                  evaluation per the simplified rule formula:
//                    F_lat = m_total * a_lateral
//                  where a_lateral = (g sin phi + a_y_cg) at the
//                  midpoint of the stack and m_total is the total
//                  stack mass. Lashing-system racking deflection
//                  delta = F / k_total where k_total is the combined
//                  lashing stiffness.

pub const container_stack = @import("container_stack.zig");

test {
    _ = container_stack;
}
