# Yard Fleet

`yard_fleet` is the first executable R1/R2 slice for generic multi-vessel
engineering studies:

- deterministic compilation of mixed vessel candidates;
- broad archetype envelopes for large-deck carriers, cruisers, destroyers,
  merchant vessels, and patrol craft;
- transparent plate, stiffener, and hull-girder scantling screens;
- per-vessel linearized Fossen 6-DOF mass, damping, and restoring terms;
- generic propulsion layouts derived from declared dimensions and power;
- fleet, flotilla, squadron, division, and vessel formation hierarchy;
- waypoint following, rotated relative slots, and deterministic closest-point
  separation intervention;
- shared RK4 stepping through Yard's existing `fossen-6dof` kernel;
- yaw-frame body/world transforms around the linearized kernel so formations
  remain geometrically consistent away from a zero-heading linearization.

Run the proof gate:

```sh
cd fleet
zig build test --summary all
```

## Proof boundary

The archetype envelopes are broad category sanity checks, not named-vessel
models. The scantling equations are preliminary, class-neutral screens and are
not class approval. The current dynamics use Yard's linearized, diagonal
Fossen model and a virtual-force controller. Identified nonlinear coefficients,
actuator allocation and saturation, wind, waves, and current remain
later-fidelity work.

## Safety boundary

This module is for public naval architecture, merchant operations, historical
simulation, research, and safe multi-vessel navigation. It deliberately does
not implement weapons, targeting, fire control, sensor signatures, damage
vulnerability optimization, engagement tactics, or reproduction of
contemporary named military platforms. Hierarchical control is limited to
waypoint tracking, formation keeping, and collision-risk reduction.
