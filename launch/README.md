# yard-launch-zig

Proof level: `unit-tested`

yard-launch-zig is a Zig 0.16 ship-launching kernel covering three
launch modes: end-launch (stern-first slipway) energy balance,
pivoting (stern lift-off + forward-cradle reaction), and side-launch
kinematics (water-contact velocity + maximum heel + deck-edge
verdict).

## What it does

### End-launch

- `end_launch.slidingAccelerationMPS2(alpha, mu, g)` returns
  `g (sin alpha - mu cos alpha)`.
- `end_launch.wayEndVelocityMPerS(a, L)` returns `sqrt(2 a L)`
  (clamped to zero when net acceleration is non-positive).
- `end_launch.wayEndKineticEnergyJ(m, v)` returns `0.5 m v^2`.
- `end_launch.velocityFromGeometry(alpha, mu, L, g)` composer.

### Pivoting

- `pivoting.buoyancyAtImmersionN(rho, g, A_W, d_imm)` linear
  immersion estimator.
- `pivoting.sternLiftedOff(B, W, L_cg, L_aft, L_fore)` returns true
  when buoyancy exceeds the required fraction of weight.
- `pivoting.forwardCradleReactionN(W, L_cg, L_aft, L_fore)` lever-
  rule reaction.

### Side-launch

- `side_launch.waterContactVelocityMPerS(H, g)` returns `sqrt(2 g H)`.
- `side_launch.maximumHeelAngleRad(v, GM, g)` returns
  `sqrt(v^2 / (g GM))` (linear-stiffness small-angle).
- `side_launch.maxHeelFromSlipway(H, GM, g)` composer.
- `side_launch.heelVerdict(phi_max, phi_deck_edge)` pass / fail.

## What it is not (v0.0.0)

- No hydrodynamic added-mass effect during launch (the kernel uses
  rigid-body kinetics).
- No water-resistance / drag on the ship as it enters the water.
- No detailed cradle-shape contact mechanics.
- No transient pitch / heave time-history.
- No trigger-mechanism / hold-back rope analysis.
- No multi-slipway launch (single-track only).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 34/34 tests passed`.

## Public API

```zig
const yard = @import("yard_launch");

// End-launch.
const alpha = std.math.atan(@as(f64, 1.0 / 18.0));
const v_we = try yard.end_launch.velocityFromGeometry(alpha, 0.02, 200.0, 9.81);
const E_k = try yard.end_launch.wayEndKineticEnergyJ(5000.0, v_we);

// Pivoting.
const R_fwd = try yard.pivoting.forwardCradleReactionN(
    50_000_000.0, 55.0, 30.0, 80.0);
const lifted = try yard.pivoting.sternLiftedOff(
    25_000_000.0, 50_000_000.0, 55.0, 30.0, 80.0);

// Side-launch.
const phi_max = try yard.side_launch.maxHeelFromSlipway(2.0, 1.5, 9.81);
const v = try yard.side_launch.heelVerdict(phi_max, std.math.pi / 6.0);
```

## Validation

- Sliding acceleration at alpha = 0 and mu = 0 is zero.
- Sliding acceleration negative when mu > tan(alpha) (won't slide).
- Typical 1:18 slipway with mu = 0.02 gives a in [0.2, 0.5] m/s^2.
- Way-end velocity sqrt(2 a L) closed form.
- Way-end velocity scales with sqrt(L).
- Way-end kinetic energy at 5000 t and 12 m/s = 3.6e8 J.
- Buoyancy linear in immersion depth.
- Stern lift-off detected at correct threshold; inclusive boundary
  returns true.
- Forward cradle reaction is W/2 at CG mid-span; W at CG = fore
  cradle; 0 at CG = aft cradle.
- Side-launch v_contact `sqrt(2 g H)`.
- Max-heel proportional to v and inversely to sqrt(GM).
- Heel verdict pass below deck-edge; fail at or above.
- Typed-error rejection for declivity > pi/4, mu > 1, zero L /
  height / GM / displacement, degenerate cradle span, CG outside
  span.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Munro-Smith, R. (1981). *Ships and Naval Architecture*.
  IMarEST.
- Watson, D. G. M. (1998). *Practical Ship Design*. Elsevier.
- Eyres, D. J., Bruce, G. J. (2012). *Ship Construction*. 7th ed.,
  Butterworth-Heinemann.
- Schneekluth, H., Bertram, V. (1998). *Ship Design for Efficiency
  and Economy*. 2nd ed., Butterworth-Heinemann.

## License

Apache-2.0.
