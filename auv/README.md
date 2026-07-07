# yard-auv-zig

Proof level: `unit-tested`

AUV / underwater glider kernel: low-Re hydrodynamics + PD depth
control + battery endurance + sea-glider polar.

## Modules

- `hydrodynamics` — Re from V/L/nu, Schlichting + ITTC-57 friction
  lines, total drag with form factor + appendage.
- `depth_control` — PD law with delta clamp, steady-state vertical
  velocity, depth-error time constant.
- `endurance` — propulsion power D V / eta, battery endurance,
  range, optimal cruise speed (cube-root of P_hotel scaling).
- `glider` — glide angle atan(1/(L/D)), glide speed from net
  buoyancy, horizontal range per leg = delta_z * L/D, vertical rate.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 49/49 tests passed`.

## References

- Fossen, T. I. (2011). *Handbook of Marine Craft Hydrodynamics and
  Motion Control*. Wiley.
- Stommel, H. (1989). *The Slocum Mission*. Oceanography 2.
- Eriksen, C. C. et al. (2001). *Seaglider: A long-range autonomous
  underwater vehicle for oceanographic research*. IEEE J. Oceanic
  Eng. 26.

AGPL-3.0-or-later.
