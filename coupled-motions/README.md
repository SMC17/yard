# yard-coupled-motions-zig

Proof level: `unit-tested`

yard-coupled-motions-zig is a Zig 0.16 3-DOF coupled-motion solver for
heave, pitch, and roll in the frequency domain. Given mass `M`,
added-mass `A`, damping `B`, restoring `C` matrices and complex forcing
`F`, it solves the impedance equation
`[-(M + A) omega^2 + i B omega + C] X = F` for the complex response
vector `X`.

## What it does

- `coupled.Complex` minimal complex-number primitive with `add`, `sub`,
  `mul`, `div`, `abs`.
- `coupled.solveRAO(M, A, B, C, F, omega)` builds the complex 3x3
  impedance matrix and solves via Gauss elimination with partial
  pivoting on the complex system. Returns the complex 3-vector
  response.
- `coupled.raoMagnitudes(X)` per-DOF response modulus.

## What it is not (v0.0.0)

- No general N-DOF generalisation (this is locked to 3-DOF for the
  heave-pitch-roll triad).
- No frequency-dependent `A(omega)`, `B(omega)` lookup (caller passes
  the matrices already evaluated at `omega`).
- No automatic spectrum convolution (compose with
  `yard-rao-spectrum-zig`).
- No forward-speed encounter-frequency mapping (caller pre-computes).
- No solver for higher-order viscous roll damping (linearised only).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_coupled_motions");

const M: yard.coupled.Matrix3 = .{ .{1,0,0}, .{0,1,0}, .{0,0,1} };
const A: yard.coupled.Matrix3 = .{ .{0,0,0}, .{0,0,0}, .{0,0,0} };
const B: yard.coupled.Matrix3 = .{ .{0.1,0,0}, .{0,0.1,0}, .{0,0,0.1} };
const C: yard.coupled.Matrix3 = .{ .{10,1,0}, .{1,10,0}, .{0,0,10} };
const F: yard.coupled.Force3 = .{
    .{ .re = 1, .im = 0 },
    .{ .re = 0, .im = 0 },
    .{ .re = 0, .im = 0 },
};
const x = try yard.coupled.solveRAO(M, A, B, C, F, 1.5);
const mag = yard.coupled.raoMagnitudes(x);
```

## Validation

- Identity impedance (`C = I`, all other zero, omega=0) reproduces
  `X = F` to 1e-12.
- Block-diagonal matrices decouple to three 1-DOF closed-form RAOs
  matching the formula
  `X_i = F_i / [-(M_i+A_i) omega^2 + i B_i omega + C_i]` to 1e-10.
- Off-diagonal coupling in `C` induces a nonzero response in the
  unforced DOF and modifies the forced DOF.
- Quasi-static low-omega limit matches `C^{-1} F` to 1e-6.
- High-omega limit drives response toward zero.
- Resonance peak at `omega_n = sqrt(C_ii / (M_ii+A_ii))` exceeds the
  off-resonance response by more than a factor of ten with light
  damping.
- Singular impedance detection at the undamped natural frequency of
  the embedded 1-DOF.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Salvesen, N., Tuck, E. O., Faltinsen, O. (1970). *Ship Motions and
  Sea Loads*. Trans. SNAME 78.
- Faltinsen, O. (1990). *Sea Loads on Ships and Offshore Structures*.
  Cambridge.
- Journee, J. M. J., Massie, W. W. (2001). *Offshore Hydromechanics*.
  Delft.

## License

AGPL-3.0-or-later.
