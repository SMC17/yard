# yard-tug-zig

Proof level: `unit-tested`

yard-tug-zig is a Zig 0.16 escort-tug performance kernel. Three
modules: `bollard` for the static bollard pull regression and tug-
type catalogue; `indirect` for the Reverse Arrest effective-force
decomposition at tow-line / heel angles; `effective` for the speed-
dependent bollard-pull degradation and the operational verdict.

## What it does

### Bollard pull

- `bollard.TugType` enum (Conventional / ASD / VSP / Escort) with
  `bollardCoefficient()` returning kN per kW.
- `bollard.bollardPullKN(P_brake, ttype)` returns `k_BP P_brake`.
- `bollard.bollardPullCustomKN(P_brake, k_bp)` for non-standard
  coefficients.
- `bollard.bollardPullToTonnesForce(BP_kN)` returns kN / 9.80665.
- `bollard.thrustToWeightRatio(BP, m_tug)` returns BP / (m g).

### Indirect / steering / braking modes

- `indirect.effectiveForceKN(BP, beta, theta)` returns
  `BP sin(beta) cos(theta)`.
- `indirect.steeringMomentKNm(F_eff, L_line, theta)` returns
  `F_eff L_line sin(theta)`.
- `indirect.brakingForceKN(BP, beta)` returns
  `BP sin(beta)` (theta = 0 limit).

### Speed-dependent effectiveness

- `effective.bollardAtSpeedKN(BP_0, V, V_max)` returns
  `BP_0 max(0, 1 - V / V_max)`.
- `effective.typicalVMaxMPerS(ttype)` returns typical V_max.
- `effective.assistanceVerdict(BP_eff, BP_req)` returns pass / fail.

## What it is not (v0.0.0)

- No tug-vessel interaction (assisted-ship wake / squat) effects on
  bollard pull.
- No tow-line dynamic-tension envelope.
- No bollard catalog with manufacturer-specific data.
- No multi-tug allocation across the assisted vessel.
- No environmental-load (wind / current) compensation envelope.
- No 3-DOF tug-control-law evaluator.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 33/33 tests passed`.

## Public API

```zig
const yard = @import("yard_tug");

const BP_0 = try yard.bollard.bollardPullKN(3500.0, .ASD);
const BP_at_speed = try yard.effective.bollardAtSpeedKN(
    BP_0, 2.5, yard.effective.typicalVMaxMPerS(.ASD));

const F = try yard.indirect.effectiveForceKN(
    BP_at_speed, std.math.pi / 6.0, std.math.pi / 4.0);
const M = try yard.indirect.steeringMomentKNm(F, 60.0, std.math.pi / 4.0);

const v = yard.effective.assistanceVerdict(BP_at_speed, 200.0);
```

## Validation

- Conventional tug at 2000 kW gives 200 kN bollard pull.
- ASD at 2000 kW gives 240 kN.
- VSP at 2000 kW gives 260 kN.
- Escort coefficient exceeds ASD.
- Bollard pull linear in P_brake.
- Tonnes-force conversion 1 kN = 1/9.80665 tf.
- Thrust-to-weight at 240 kN / 300 t.
- Indirect F at beta = 30 deg, theta = 0 equals BP/2.
- Indirect F at beta = 0 or theta = pi/2 is zero.
- Steering moment closed form `F L sin(theta)`.
- Braking force at beta = 45 deg equals BP / sqrt(2).
- Bollard at V = 0 equals BP_0; at V = V_max is zero; at V_max/2
  is BP_0/2.
- Verdict pass at BP_eff >= BP_req.
- Typed-error rejection for non-positive power / BP / V_max,
  invalid heel / towline angle, negative speed.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Carlton, J. (2018). *Marine Propellers and Propulsion*. 4th ed.,
  Butterworth-Heinemann.
- Hensen, H. (2003). *Tug Use in Port: A Practical Guide*. Nautical
  Institute.
- Allan, R. G. (2004). *Robert Allan Ltd. Tug Design Standards*.
  IMarEST.
- OCIMF. *Recommendations for Equipment Employed in the Mooring of
  Ships at Single Point Moorings*.

## License

AGPL-3.0-or-later.
