# Status

yard-azipod-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `azipod.resolveSteeringForce` | `unit-tested` | cardinal direction closed forms at theta = 0, pi/2, pi; magnitude preservation |
| `azipod.advanceVelocity` | `unit-tested` | V_a = V (1 - w_T) closed form |
| `azipod.sideForceRatio` | `unit-tested` | tan(0) = 0; tan(pi/4) = 1 |
| `waterjet.netThrustN` | `unit-tested` | stationary 153 750 N; zero at V_j = V_in; linear in rho |
| `waterjet.propulsiveEfficiency` | `unit-tested` | 2/3 at V_j = 2 V_in; 1 at V_j = V_in |
| `waterjet.idealJetPowerW` | `unit-tested` | T (V_j + V_in) / 2 = 20 kW worked example |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `20/20 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: thrust decomposition is exact only when
  T_OW is constant over the steering range; the kernel does not
  claim sub-percent accuracy on off-design pod thrust-degradation.
  The caller composes the manufacturer's K_T-J map externally.
- Type-II missed risk guard: typed-error rejection for negative
  thrust, angle out of [-pi, pi], wake fraction >= 1, V_j < V_in,
  non-positive density.
- Type-III category guard: kinematic / momentum kernel only; not a
  cavitation predictor (use `yard-cavitation-zig`); not a multi-pod
  DP allocator; not a hull-boundary-layer interaction engine.

## What is not covered (v0.0.0)

- Off-design pod thrust-degradation curve.
- Pod / propeller interaction with hull boundary layer.
- Fish-tail / cross-flow rudder force on the strut.
- Waterjet inlet loss / cavitation.
- Reverse-thrust bucket geometry.
- Multi-pod DP control allocation.

## Composition

- Pod thrust output `(Tx_n, Ty_n)` feeds the 6-DOF state-space
  forcing of `yard-fossen-6dof-zig`.
- Waterjet thrust feeds `yard-ittc78-zig` powering chain as a
  drop-in for the propeller K_T term.
- Effective `V_a` couples to `yard-propulsion-zig` Wageningen B-series
  K_T-J map for conventional propeller comparison studies.
