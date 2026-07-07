// yard-pipeline-zig public API.
//
// stability: DNV-RP-F109 simplified on-bottom-stability check for
//            subsea pipelines. Per-unit-length hydrodynamic loads
//            from current + wave kinematics combined via the Morison
//            equation; lateral stability gate compares the required
//            submerged weight against the resisting friction and lift.
//
// cable_route_consumer: route-geometry-only wire that reads an
//            oceanman per-cable JSON record + optional landing-point
//            FeatureCollection and emits a LayPlan (waypoints +
//            great-circle segment lengths). Cable record is NOT a
//            pipeline lay plan; the wire surfaces SHARED route
//            geometry, not equivalence. See the module-level
//            disclosure in cable_route_consumer.zig.

pub const stability = @import("stability.zig");
pub const cable_route_consumer = @import("cable_route_consumer.zig");

test {
    _ = stability;
    _ = cable_route_consumer;
}
