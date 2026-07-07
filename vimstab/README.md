# yard-vimstab-zig

Proof level: `unit-tested`

yard-vimstab-zig is a Zig 0.16 container-stack lateral-load and
racking-deflection kernel per IMO MSC.252(83) (Intact Stability Code
container-stack lashing). Total stack mass; lateral acceleration
from instantaneous roll angle and lateral CG acceleration; total
lateral force; racking deflection from combined lashing stiffness;
pass / fail verdict against a permissible-deflection limit.

## What it does

- `container_stack.totalStackMassKg(tier_masses)` sums per-tier
  masses.
- `container_stack.lateralAccelerationMPS2(g, phi, a_y_cg)` returns
  `g sin phi + a_y_cg`.
- `container_stack.lateralForceN(m_total, a_lateral)` returns
  `m_total a_lateral`.
- `container_stack.rackingDeflectionM(F, k_total)` returns
  `F / k_total`.
- `container_stack.deflectionVerdict(delta, delta_allow)` returns
  pass / fail.

## What it is not (v0.0.0)

- No per-tier bending-moment / corner-post stress distribution
  (uniform stack-midpoint acceleration only).
- No CSC plate / inspection-cycle compliance.
- No dynamic-amplification factor for transient slamming.
- No twistlock / lashing-bar stiffness regression (caller supplies
  `k_total`).
- No multi-stack interaction across container bays.
- No SOLAS Ch. VI / VII compliance (IMO CSS Code companion).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 15/15 tests passed`.

## Public API

```zig
const yard = @import("yard_vimstab");

const tiers = [_]f64{ 20_000.0, 20_000.0, 20_000.0 };
const m_total = try yard.container_stack.totalStackMassKg(&tiers);
const a_lat = try yard.container_stack.lateralAccelerationMPS2(
    9.81, std.math.pi / 6.0, 0.0);  // 30 deg roll
const F = try yard.container_stack.lateralForceN(m_total, a_lat);
const delta = try yard.container_stack.rackingDeflectionM(F, 10_000_000.0);
const v = try yard.container_stack.deflectionVerdict(delta, 0.025);
```

## Validation

- 3-tier 20 t stack sums to 60 t.
- Lateral acceleration at phi=0, a_y=0 is zero.
- Lateral acceleration at phi=30 deg is `g / 2`.
- Lateral force scales linearly with mass.
- Lateral force at 60 t and 3 m/s^2 equals 180 kN.
- Racking deflection at F = 180 kN, k = 10 MN/m equals 18 mm.
- Racking deflection inversely proportional to stiffness.
- Verdict pass at delta = 18 mm vs 25 mm permissible.
- Verdict pass at exactly permissible (inclusive boundary).
- Verdict fail at 30 mm vs 25 mm.
- Typed-error rejection for zero stiffness, phi > pi/2, empty tier
  list.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO MSC.252(83). *Adoption of the Revised Code on Intact Stability
  for All Types of Ships Covered by IMO Instruments*.
- IMO CSS Code. *Code of Safe Practice for Cargo Stowage and Securing*.
- DNV CG-0117. *Container Securing*.
- Lloyd's Register Container Securing Rules.

## License

Apache-2.0.
