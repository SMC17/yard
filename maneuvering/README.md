# yard-maneuvering-zig

Proof level: `unit-tested`

yard-maneuvering-zig is a Zig 0.16 implementation of the Nomoto K-T yaw
maneuvering model: first-order step response and second-order T1/T2/T3
variant.

## What it does

- `nomoto.nomotoFirstOrderYawRate(K, T, delta_0, t)` analytical step
  response of the first-order Nomoto model.
- `nomoto.nomotoFirstOrderHeading(K, T, delta_0, t)` integrated heading.
- `nomoto.nomotoSteadyStateYawRate(K, delta_0)`.
- `nomoto.firstOrderTFromSecondOrder(T1, T2, T3)` identity T = T1+T2-T3.
- `nomoto.nomotoSecondOrderYawRate(K, T1, T2, delta_0, t)` closed-form
  second-order step response; double-root case T1 = T2 handled
  separately.

## What it is not (v0.0.0)

- No rudder-rate-dependent input (T3 d delta_r / dt is zero for a step;
  caller can wrap if needed).
- No full Fossen 6-DOF state-space.
- No DP / autopilot / Kalman filter.
- No zig-zag maneuver simulator (analytical overshoot estimate deferred).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 15/15 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

Sample on a laptop with load average 5-22:

```
nomoto.firstOrderYawRate         iters=1000000   ns/call=   49.3
```

## Public API

```zig
const yard = @import("yard_maneuvering");

// Mariner-class example: K = 0.18, T = 14 s. Apply 10 deg rudder.
const delta_0 = 10.0 * std.math.pi / 180.0;
const r_30s = try yard.nomoto.nomotoFirstOrderYawRate(0.18, 14.0, delta_0, 30.0);
const psi_30s = try yard.nomoto.nomotoFirstOrderHeading(0.18, 14.0, delta_0, 30.0);
```

## Validation

- First-order yaw rate at t = T equals (1 - 1/e) * K * delta_0 within
  0.1 percent (the canonical time-constant property of a first-order
  exponential response).
- First-order yaw rate at large t equals K * delta_0 to f64 round-off.
- First-order heading scales linearly with delta_0.
- Second-order with double-root T1 = T2 produces zero at t = 0 and
  K * delta_0 at large t.
- Second-order with T2 << T1 approaches steady state at finite t much
  greater than T2 (within 5 percent), since the fast mode has decayed.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- Nomoto, K. et al. (1957), "On the steering qualities of ships,"
  International Shipbuilding Progress 4:35, pp 354-370.
- Fossen, T. I. (2011), *Handbook of Marine Craft Hydrodynamics and
  Motion Control*, Wiley, Ch. 7.
- Codex cross-references at
  `~/codex/concepts/nomoto-maneuvering-model.md`.

## License

Apache-2.0. See `LICENSE`.
