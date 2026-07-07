# yard-irf-zig

Proof level: `unit-tested`

yard-irf-zig is a Zig 0.16 Cummins / Ogilvie time-domain motion-
equation kernel. Given a frequency-dependent damping coefficient
`B(omega)` it computes the impulse-response (retardation) function
`K(t)` via inverse cosine transform on a uniform omega grid, recovers
the infinite-frequency added mass `A_infinity` from a reference
frequency, and exposes a single forward-Euler step of the Cummins
equation suitable for free-decay or external-forcing time histories.

## What it does

- `cummins.retardationFunctionAtT(omega, B, t)` evaluates
  `K(t) = (2/pi) integral_0^inf B(omega) cos(omega t) domega` on a
  uniform omega grid via trapezoidal quadrature.
- `cummins.buildRetardationArray(omega, B, t_arr, K_out)` fills an
  output K array on an arbitrary t grid.
- `cummins.addedMassInfinity(A_at_ref, omega_ref, t_arr, K_arr)`
  recovers `A_infinity` from a reference-frequency `A(omega_ref)` and
  the previously computed K(t) array via the Ogilvie 1964 sine-
  integral identity.
- `cummins.cumminsStep(M_eff, C, F, x, v, mem, dt)` advances one
  forward-Euler step of the time-domain motion equation. The caller
  is responsible for maintaining the velocity-history convolution
  `mem = integral_0^t K(t - tau) dot{x}(tau) dtau`.

## What it is not (v0.0.0)

- No FFT-based K(t) (this is direct quadrature).
- No automatic velocity-history convolution (caller maintains the
  running convolution).
- No state-space realisation of K(t) (Prony / vector-fitting deferred).
- No multi-DOF coupling (single-DOF only; multi-DOF should compose
  externally with `yard-coupled-motions-zig`).
- No higher-order time integrator (RK4 deferred to a downstream
  kernel).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_irf");

const K0 = try yard.cummins.retardationFunctionAtT(&omega, &B, 0.0);

var K_arr: [N]f64 = undefined;
try yard.cummins.buildRetardationArray(&omega, &B, &t_arr, &K_arr);

const A_inf = try yard.cummins.addedMassInfinity(A_ref, omega_ref, &t_arr, &K_arr);

const new = try yard.cummins.cumminsStep(
    M + A_inf, C_restoring, F_t, x, v, mem, dt);
```

## Validation

- `K(0)` for constant `B = 5` over [0.1, 3.0] reproduces
  `(2/pi) * 5 * 2.9` to 1e-9 (trapezoidal rule is exact for a
  constant integrand on a uniform grid).
- Delta-bump B at omega_p = 1.0 reproduces the
  `(2/pi) B_p domega cos(omega_p t)` approximation to 0.1.
- `buildRetardationArray` populates a t grid with K(0) the largest
  magnitude entry.
- `addedMassInfinity` for an identically zero K array returns the
  caller-supplied `A_at_ref` reference.
- Cummins step ballistic motion (zero memory, zero stiffness)
  reduces to forward-Euler `a = F/M`.
- Cummins step linear-restoring case `M = 1, C = 10, x = 1` produces
  `v_new = -0.1`, `x_new = 0.999`.
- Memory term contribution: doubling `mem` from 0 to 5 changes
  `v_new` from -0.1 to -0.15.
- Typed-error rejection for non-positive mass / step / omega_ref,
  unequal-length omega-B, and non-uniform t spacing.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Cummins, W. E. (1962). *The Impulse Response Function and Ship
  Motions*. Schiffstechnik 9.
- Ogilvie, T. F. (1964). *Recent Progress Toward the Understanding
  and Prediction of Ship Motions*. 5th ONR Symposium on Naval
  Hydrodynamics.
- Journee, J. M. J., Massie, W. W. (2001). *Offshore Hydromechanics*.
  Delft.
- Faltinsen, O. (1990). *Sea Loads on Ships and Offshore Structures*.
  Cambridge.

## License

Apache-2.0.
