# yard-deicing-zig

Proof level: `unit-tested`

yard-deicing-zig is a Zig 0.16 marine-superstructure icing kernel.
Two modules: `overland` computes the Overland 1986 icing-predictor
index PR and classifies it into none / light / moderate / heavy /
extreme; `accreted` evaluates accreted ice weight per surface area
and total weight gain over an exposure duration.

## What it does

### Overland predictor

- `overland.T_freeze_seawater_deg_c = -1.7`.
- `overland.predictorIndex(V_wind, T_air, T_sea)` returns
  `V (T_freeze - T_air) / (1 + 0.4 (T_sea - T_freeze))` or 0 when
  air is warmer than the freezing point.
- `overland.IcingClass` enum.
- `overland.classifyByIndex(PR)` maps PR to a class using the
  cutoffs 0 / 22.4 / 53.3 / 83.0.
- `overland.classifyByConditions(V, T_air, T_sea)` composes both
  steps.

### Accreted weight

- `accreted.rho_ice_seawater_spray_kg_per_m3 = 900`.
- `accreted.accretedMassKg(rho, h, A)` returns `rho h A`.
- `accreted.accretionRateMperHrForClass(cls)` indicative rates
  (0 / 0.003 / 0.010 / 0.020 / 0.040 m/hr).
- `accreted.totalAccretedWeightKg(rho, rate, duration, A)` returns
  `rho rate duration A`.

## What it is not (v0.0.0)

- No mixed-phase (sea-spray + atmospheric) accretion model.
- No de-icing-system sizing (heat-trace / IR / mechanical).
- No KG / metacentric-height impact (compose with
  `yard-stability-zig` on the total accreted weight).
- No directional spray-zone map.
- No IMO Polar Code icing-allowance lookup.
- No anti-icing chemistry / freezing-point depression.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 22/22 tests passed`.

## Public API

```zig
const yard = @import("yard_deicing");

const cls = try yard.overland.classifyByConditions(15.0, -10.0, 5.0);
const rate = yard.accreted.accretionRateMperHrForClass(cls);
const W = try yard.accreted.totalAccretedWeightKg(
    yard.accreted.rho_ice_seawater_spray_kg_per_m3,
    rate, 12.0, 100.0);
```

## Validation

- Predictor zero when air is warmer than freezing.
- Closed-form PR at V=15, T_air=-10, T_sea=5: ~ 33.83.
- PR scales linearly with wind speed.
- Class boundaries map PR = 22.4 / 53.3 / 83.0 to the published
  cutoffs.
- Class ordering: rate(none) < rate(light) < rate(moderate) <
  rate(heavy) < rate(extreme).
- Accreted mass at standard density, 10 mm ice, 100 m^2 = 900 kg.
- Accreted mass scales linearly in thickness and area.
- Total accreted weight at 10 mm/hr, 12 hr, 100 m^2 equals 10 800
  kg.
- Total accreted weight scales linearly in duration.
- Typed-error rejection for negative wind speed, extreme
  temperature, zero thickness, zero duration.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Overland, J. E. (1986). *Prediction of Vessel Icing*. NOAA
  Technical Memorandum NWS AR-37.
- Comiskey, A. L., Kelley, J. J. (1989). *Vessel-Icing Atlas for
  the Bering Sea, Gulf of Alaska, and Aleutian Region*.
- IMO International Code for Ships Operating in Polar Waters
  (Polar Code), Part I-A Ch. 2.
- ISO 19906. *Petroleum and Natural Gas Industries: Arctic Offshore
  Structures*.

## License

AGPL-3.0-or-later.
