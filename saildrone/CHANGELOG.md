# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `stability.gzWallSidedM`, `phiMaxGZRadInRange`, `phiMaxGZRad`,
  `maxGZM`, `imoUsvDraftVerdict`.
- `beaufort.beaufortWindSpeed` WMO scales 0..12.
- `beaufort.C_L_close_hauled`, `heelingMomentNm`,
  `heelingMomentFromBeaufortNm`.
- `energy.solarPowerW`, `dailyEnergyWh`, `batteryAutonomyDays`,
  `netDailyEnergyWh`.
- `energy.I_avg_north_atlantic`, `I_avg_mediterranean`,
  `I_avg_equatorial`, `I_avg_arctic_summer`.
- `energy.eta_pv_si_default = 0.22`.
- 36-test unit suite including wall-sided GZ closed form, USV
  verdict pass/fail cases, Beaufort scale lookup + V^2 heeling
  moment, solar production / autonomy / regional ordering, and
  typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

IMO USV Code thresholds, Beaufort table, regional insolation, and
PV efficiency all flagged `claimed`.
