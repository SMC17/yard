# yard-saildrone-zig

Proof level: `unit-tested`

yard-saildrone-zig is a Zig 0.16 USV / unmanned wind-powered surface
vehicle kernel. Three modules: `stability` for the wall-sided GZ
approximation and IMO USV Code (draft) verdict; `beaufort` for the
Beaufort wind-scale lookup and sail heeling moment; `energy` for the
solar-power production, daily-energy balance, battery autonomy.

## What it does

### Stability

- `stability.gzWallSidedM(GM, BM_T, phi)` evaluates
  `(GM + 0.5 BM_T tan^2 phi) sin phi`.
- `stability.phiMaxGZRadInRange(GM, BM_T, phi_max_deg)` brute-force
  search for the maximum-GZ angle up to a caller-supplied ceiling.
- `stability.phiMaxGZRad(GM, BM_T)` 30-deg deck-edge ceiling.
- `stability.maxGZM(GM, BM_T)` returns the max GZ over the range.
- `stability.imoUsvDraftVerdict(GM, BM_T)` returns pass / fail
  against `GM >= 0.15 m AND GZ_max >= 0.20 m`.

### Beaufort wind scale

- `beaufort.beaufortWindSpeed(n)` returns the WMO 1946 wind-speed
  midpoint at scale n.
- `beaufort.C_L_close_hauled = 1.2` default sail-trim lift
  coefficient.
- `beaufort.heelingMomentNm(rho, v, A_s, C_L, h_sail)` evaluates
  `0.5 rho v^2 A_s C_L h_sail`.
- `beaufort.heelingMomentFromBeaufortNm(n, A_s, h_sail)` composer.

### Energy budget

- `energy.solarPowerW(A, I, eta)` returns `A I eta`.
- `energy.dailyEnergyWh(P)` returns `24 P`.
- `energy.batteryAutonomyDays(C, L)` returns `C / L`.
- `energy.netDailyEnergyWh(P, L_daily)` returns net.
- Regional insolation constants and `eta_pv_si_default = 0.22`.

## What it is not (v0.0.0)

- No full nonlinear GZ curve (compose with `yard-stability-zig` for
  the proper hydrostatic GZ integration).
- No sea-state response (compose with `yard-rao-spectrum-zig`).
- No control-allocation / autopilot loop.
- No mission-planning routing optimiser.
- No data-link / SATCOM bandwidth budget.
- No payload-instrumentation power profiling.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 36/36 tests passed`.

## Public API

```zig
const yard = @import("yard_saildrone");

const gz_max = try yard.stability.maxGZM(0.30, 1.5);
const v_stab = try yard.stability.imoUsvDraftVerdict(0.30, 1.5);

const M_h = try yard.beaufort.heelingMomentFromBeaufortNm(6, 5.0, 3.0);

const P_solar = try yard.energy.solarPowerW(
    2.0, yard.energy.I_avg_north_atlantic, yard.energy.eta_pv_si_default);
const net = try yard.energy.netDailyEnergyWh(P_solar, 800.0);
const days = try yard.energy.batteryAutonomyDays(2000.0, 800.0);
```

## Validation

- GZ at phi=0 is zero.
- GZ closed-form match at phi=30 deg, GM=0.5, BM_T=2.
- GZ at small angle reduces to GM sin phi.
- phi_max within the 1-30 deg search range.
- Max GZ at typical USV stays within physical range.
- USV verdict pass with high GM + BM_T; fail with low GM; fail with
  low BM_T.
- Beaufort 0 = 0.15 m/s; Beaufort 12 = 34 m/s; monotone increasing.
- Beaufort 13+ rejected.
- Heeling moment closed form; V^2 / area / height linear scaling.
- Beaufort composer reproduces composed call.
- Beaufort 8 / Beaufort 4 heeling-moment ratio in [5, 10].
- Solar power 88 W at 2 m^2, 200 W/m^2, 22 % efficiency.
- Solar power linear in A and I.
- Daily energy 88 W * 24 = 2112 Wh.
- Battery autonomy 1000 Wh / 200 Wh/day = 5 days.
- Net daily energy positive / negative cases.
- Regional insolation ordering: equator > Mediterranean > Atlantic
  > Arctic.
- Typed-error rejection for non-positive GM / BM / area / capacity
  / load, eta > 1, Beaufort out of range, phi >= pi/2.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO MSC.1/Circ.1638 (under development). *Guidelines for Maritime
  Autonomous Surface Ships*.
- Bertram, V., Schneekluth, H. (1998). *Ship Design for Efficiency
  and Economy*. 2nd ed., Butterworth-Heinemann.
- WMO Manual on Codes 306. *Beaufort scale of wind force*.
- Marsh, J. (2015). *Sailing Drones*. Hydro International 19.
- Saildrone Inc. (2018-2024). *Mission Reports*.

## License

AGPL-3.0-or-later.
