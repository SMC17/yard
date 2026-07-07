# yard-strength-zig

Proof level: `unit-tested`

yard-strength-zig is a Zig 0.16 implementation of IACS Unified
Requirement S11 longitudinal-strength formulas plus the UR S4 material
factor for steel grades.

## What it does

- Wave coefficient `C` as a piecewise function of rule length L,
  defined for 90 to 500 m per UR S11.
- Wave bending moments `M_wv_hog` and `M_wv_sag` in kN*m.
- UR S4 material factor `k` and permissible stress 175 / k (MPa)
  per steel grade (mild, HT32, HT36, HT40).
- Minimum hull-girder section modulus `Z_min` from a design moment
  and a steel grade.
- Minimum hull-girder moment of inertia `I_min = 3 Z_min L`.

## What it is not (v0.0.0)

This release covers the rule-formula side of UR S11. The following are
deferred:

- Shear-stress check `t >= (S_w + S_sw) a_v / (I tau_perm)`.
- Buckling checks (plate, column, torsional) per UR S11 + RP-C201.
- UR S11A containership-specific provisions (warping torsion, hatch
  corners).
- UR S25 corrosion deduction for bulk carriers and oil tankers.
- Still-water bending moment from loading manual (caller-supplied).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 16/16 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

## Public API

```zig
const yard = @import("yard_strength");
const s11 = yard.ur_s11;

const C = try s11.waveCoefficient(200.0);             // 9.75
const M_hog = try s11.waveMomentHog(200.0, 32.0, 0.85, 1.0);
const M_sag = try s11.waveMomentSag(200.0, 32.0, 0.85, 1.0);
const sigma = s11.permissibleStressMpa(.ht32);        // 175 / 0.78
const Z = try s11.minSectionModulus(M_hog, .mild);
const I = s11.minMomentOfInertia(Z, 200.0);
```

## Validation against codex substrate

The Hughes/Paik (2010) Ch. 4 worked example for a bulker with
L = 200 m, B = 32 m, C_B = 0.85, f1 = 1.0 produces:

- C = 9.75
- M_wv_hog ~ 2,015,500 kN*m (Hughes/Paik value: ~ 2,016,000)
- M_wv_sag ~ -2,127,800 kN*m (Hughes/Paik value: ~ -2,127,000)

The tests cross-check both moments against these reference values.

Wave coefficient C is verified continuous at L = 300 m and L = 350 m
(the boundaries between the three branches).

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- IACS Unified Requirement S11 (Longitudinal Strength). Latest
  revision at iacs.org.uk.
- IACS Unified Requirement S4 (Material factor table).
- Hughes, O. F. and Paik, J. K. (2010), *Ship Structural Analysis and
  Design*, SNAME, Ch. 4.
- Mansour, A. and Liu, D. (2008), *Strength of Ships and Ocean
  Structures*, PNA series, SNAME.
- Codex cross-references at
  `~/codex/concepts/iacs-ur-s11-longitudinal-strength.md` and
  `~/codex/sources/standards_machine_readable/iacs_ur_s11_longitudinal_strength.yaml`.

## License

Apache-2.0. See `LICENSE`.
