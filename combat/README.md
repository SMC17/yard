# yard-combat-zig

Proof level: `unit-tested`

Naval combat-systems kernel: radar cross-section primitives, weapon-launch
reaction, magazine quantity-distance safety.

## What it does

- `rcs` — flat plate / sphere / trihedral corner reflector RCS; free-space
  radar range; antenna gain from aperture; dBsm conversion.
- `weapon` — gun recoil impulse + mean force; muzzle energy; VLS deck
  pressure; vacuum projectile time-to-apex and max range.
- `magazine` — STANAG 4439 / AASTP-1 quantity-distance K-factors
  (IBD/PTRD/IMD/IMD-shielded); MCE bookkeeping; separation verdict.

## What it is not

Not an engagement simulator, fire-control system, or survivability analysis
suite. RCS models are textbook geometric approximations — not full-wave or
measurement-correlated signatures. Magazine Q-D checks are simplified K-factor
arithmetic — not an explosives safety case acceptable to a national authority
without qualified review.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 42/42 tests passed`.

## References

- Skolnik, M. I. (2008). *Radar Handbook*. 3rd ed., McGraw-Hill.
- Knott, E. F. et al. (2004). *Radar Cross Section*. 2nd ed., SciTech.
- NATO AASTP-1. *Manual of NATO Safety Principles for the Storage of Military
  Ammunition and Explosives*.
- US DoD 6055.09-M. *DoD Ammunition and Explosives Safety Standards*.

## License

Apache-2.0. See `LICENSE`.