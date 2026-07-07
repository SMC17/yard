# yard-strip-theory-zig

Proof level: `unit-tested`

yard-strip-theory-zig is a Zig 0.16 frequency-domain 1-DOF heave
equation solver. The complex response amplitude X(omega) per unit wave
amplitude is the inverse of the impedance
`-(M + A_33) omega^2 + i B_33 omega + C_33`.

## What it does

- `heave.Complex` typed complex number with magnitude method.
- `heave.responseAmplitude(M, A_33, B_33, C_33, F_3, omega)` returns
  X(omega) given mass, added mass, damping, restoring, and complex
  forcing.
- `heave.raoModulus(...)` returns the heave RAO modulus |X(omega)|.
- `heave.naturalFrequency(M, A_33, C_33)` undamped natural frequency.

## What it is not (v0.0.0)

- No 6-DOF coupled equations of motion (heave + pitch + roll).
- No strip-theory integration of per-station 2D added mass and
  damping to the global A_jk and B_jk (caller supplies the totals).
- No Salvesen-Tuck-Faltinsen forward-speed correction terms.
- No Lewis-form 2D added-mass approximation (caller supplies A_33).
- No JONSWAP / Pierson-Moskowitz convolution for response spectra
  (compose with yard-seakeeping-zig externally).
- No irregular-wave statistics.

## Composition with yard-seakeeping-zig and yard-hydro-zig

This library is intentionally standalone. Cross-port composition:

- Restoring `C_33 = rho * g * A_W` where A_W comes from
  `yard-hydro-zig.integrate.waterplaneAreaFromHalfBreadths` or
  `yard-hydro-zig.wigley.Hull.waterplaneArea`.
- Wave-spectrum convolution: compose with `yard-seakeeping-zig`
  spectra to get response variance via integral of |X(omega)|^2 *
  S_zeta(omega) domega.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_strip_theory");

const F: yard.heave.Complex = .{ .re = 1.0e5, .im = 0.0 };
const x = try yard.heave.responseAmplitude(
    1.0e6, 5.0e5, 1.0e4, 2.0e5, F, 0.6,
);
const rao = try yard.heave.raoModulus(
    1.0e6, 5.0e5, 1.0e4, 2.0e5, F, 0.6,
);
const omega_n = try yard.heave.naturalFrequency(1.0e6, 5.0e5, 2.0e5);
```

## Validation

- At long-wave limit (omega -> 0) with F = C_33 (Froude-Krylov
  balance), RAO approaches 1 within 0.1 percent.
- At the natural frequency omega_n, RAO equals |F| / (B_33 * omega_n)
  to f64 round-off (the imaginary part of the denominator dominates).
- RAO peaks near omega_n: tested against omega = 0.5 omega_n and 2
  omega_n.
- At very high omega, RAO decays toward zero (less than 1e-3 at omega
  = 100 in the sample test).
- RAO modulus is independent of forcing phase at fixed |F|.
- RAO is linear in |F|.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Salvesen, N., Tuck, E.O., and Faltinsen, O.M. (1970), "Ship motions
  and sea loads," Transactions SNAME 78: 250-287.
- Faltinsen, O.M. (1990), *Sea Loads on Ships and Offshore Structures*,
  Cambridge UP, Ch. 5-6.
- Newman, J.N. (1977), *Marine Hydrodynamics*, MIT Press, Ch. 6.
- Codex cross-references at
  `~/codex/concepts/salvesen-tuck-faltinsen-strip-theory.md`.

## License

Apache-2.0.
