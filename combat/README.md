# yard-combat-zig

Proof level: `unit-tested`

Naval combat-systems kernel: radar cross-section primitives, weapon-
launch reaction, magazine quantity-distance safety.

## Modules

- `rcs` — Flat plate / sphere / trihedral corner reflector RCS;
  free-space radar range; antenna gain from aperture; dBsm conversion.
- `weapon` — Gun recoil impulse + mean force; muzzle energy; VLS
  deck pressure; vacuum projectile time-to-apex and max range.
- `magazine` — STANAG 4439 / AASTP-1 quantity-distance K-factors
  (IBD/PTRD/IMD/IMD-shielded); MCE bookkeeping; separation verdict.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 42/42 tests passed`.

## References

- Skolnik, M. I. (2008). *Radar Handbook*. 3rd ed., McGraw-Hill.
- Knott, E. F. et al. (2004). *Radar Cross Section*. 2nd ed.,
  SciTech.
- NATO AASTP-1. *Manual of NATO Safety Principles for the Storage
  of Military Ammunition and Explosives*.
- US DoD 6055.09-M. *DoD Ammunition and Explosives Safety
  Standards*.

Apache-2.0.
