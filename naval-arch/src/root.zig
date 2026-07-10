//! yard-naval-arch — shared types and units for yard composition.
//!
//! Primitive modules (hydro, stability, resistance, …) stay independent.
//! This package defines the interchange contract for compose/ and examples/.

pub const types = @import("types.zig");
pub const units = @import("units.zig");

// Re-export commonly used types at package root.
pub const PhysicalConstants = types.PhysicalConstants;
pub const PrincipalParticulars = types.PrincipalParticulars;
pub const TankSpec = types.TankSpec;
pub const LoadingCondition = types.LoadingCondition;
pub const Hydrostatics = types.Hydrostatics;
pub const StabilitySummary = types.StabilitySummary;
pub const GzSample = types.GzSample;
pub const IsCodeResult = types.IsCodeResult;
pub const ValidityFlag = types.ValidityFlag;
pub const ValidityFlags = types.ValidityFlags;
pub const ProofLevel = types.ProofLevel;
pub const RegulatoryExclusion = types.RegulatoryExclusion;
pub const RegulatoryExclusions = types.RegulatoryExclusions;
pub const RegulatoryBoundary = types.RegulatoryBoundary;

test {
    _ = types;
    _ = units;
}