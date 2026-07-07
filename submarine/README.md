# yard-submarine-zig

Proof level: `unit-tested`

Submarine kernel: pressure-hull collapse (von Mises) + hydrostatic
dive equation + main-ballast-tank sizing + trim compensation.

## Modules

- `pressure_hull` — hydrostatic pressure, hoop stress, yield-
  collapse pressure, von Mises critical buckling for lobe n,
  crush depth, operating depth with safety factor.
- `dive` — seawater density profile (depth-corrected), net
  buoyancy, quasi-steady ascent velocity, simplified decompression-
  stop estimator.
- `ballast` — MBT capacity from surfaced vs submerged displacement,
  reserve-buoyancy fraction, trim-transfer mass between
  compensating tanks, compensating water volume.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 40/40 tests passed`.

## References

- Burcher, R., Rydill, L. (1994). *Concepts in Submarine Design*.
  Cambridge.
- Renkenberger, P. R. (2014). *Submarine Hydrodynamics*. Springer.
- Friedman, N. (1994). *U.S. Submarines Since 1945*. Naval
  Institute Press.
- US Navy. *Diving Manual* Rev. 7.

AGPL-3.0-or-later.
