# yard-propulsion-zig

Proof level: `unit-tested`

yard-propulsion-zig is a Zig 0.16 evaluator for the Wageningen B-series
open-water propeller coefficients K_T and K_Q, with the Reynolds-number
correction. Pure polynomial; allocator-free.

## What it does

- Evaluates K_T(J, P/D, A_E/A_0, Z) over the 39-term Oosterveld 1975
  polynomial. K_T is the dimensionless thrust coefficient.
- Evaluates K_Q(J, P/D, A_E/A_0, Z) over the 47-term polynomial. K_Q is
  the dimensionless torque coefficient.
- Computes open-water propulsive efficiency
  `eta_O = (J / (2 pi)) (K_T / K_Q)`.
- Applies the Oosterveld 1975 Table 6 Reynolds correction to extrapolate
  from the reference Rn = 2.0e6 to higher Reynolds (up to roughly 2e9).
- Validates input against the B-series validity envelope
  (Z in [2, 7]; P/D in [0.5, 1.4]; A_E/A_0 in [0.30, 1.05]; J in [0, 1.5]).

## What it is not

This library does not pick a propeller. It does not compute thrust from
shaft RPM or ship resistance. It does not perform an open-water test
extrapolation chain (that is ITTC-78 territory; downstream from here).
It does not handle cavitation. Cross-port composition with a future
yard-resistance-zig produces the powering chain. Out of scope here.

## Why the polynomial matters

Wageningen B-series is the dominant publicly-available propeller series.
Every preliminary-design optimum-J search starts here. The polynomial
form is small (39 + 47 terms), evaluator-friendly, and validated against
a tank-test database that has 90+ years of continuous use.

The functional form is:

```
K_T = sum_n C_{n,T} * J^{s_n} * (P/D)^{t_n} * (A_E/A_0)^{u_n} * Z^{v_n}
K_Q = sum_n C_{n,Q} * J^{s_n} * (P/D)^{t_n} * (A_E/A_0)^{u_n} * Z^{v_n}
```

where each (C, s, t, u, v) tuple is one row of Oosterveld 1975 Table 5.

## Coefficient source and verification posture

Coefficients are transcribed from Oosterveld and van Oossanen (1975),
NSMB Publication 479, International Shipbuilding Progress Vol. 22 No. 251,
Table 5. The same tables are reprinted in Bernitsas-Ray-Kinley (1981),
UMich NA&ME Report 237 (DeepBlue handle 91702).

Eleven coefficient digits across the K_T and K_Q tables were
OCR-ambiguous on the scan ingested by the codex substrate. Those rows
are tagged `// [ocr]` in `src/wageningen.zig`. The values used are the
canonical ones downstream implementations (FreeCAD-Ship, NSMB-derived
codes) carry. The full list of OCR-ambiguous rows is in `STATUS.md`.

The lock-in regression tests (`kT regression lock at J=0`, `kQ regression
lock at J=0.6`) defend against silent coefficient regressions. They do
not assert absolute agreement with the published Bernitsas 1981 tank
data; that requires an external cross-check against a clean print of
Publication 237 or against an independent implementation.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 20/20 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

Sample numbers from a laptop with load average 242 during the run
(numbers are upper bounds, not best case):

```
kT(J,P/D,A_E/A_0,Z)              iters=200000    ns/call=  409.5
kQ(J,P/D,A_E/A_0,Z)              iters=200000    ns/call=  552.8
```

K_T has 39 polynomial terms; K_Q has 47. The cost difference scales
roughly with term count, consistent with no SIMD or other vectorization
in this v0.0.0 implementation. Future optimization opportunity: collapse
repeat sub-expressions in `powU`.

## Public API

```zig
const yard = @import("yard_propulsion");
const wag = yard.wageningen;

const kt = wag.kT(0.6, 1.0, 0.70, 4.0);
const kq = wag.kQ(0.6, 1.0, 0.70, 4.0);
const eta = wag.etaO(0.6, kt, kq);

// Reynolds correction above Rn = 2e6.
const dkt = wag.deltaKT(0.6, 1.0, 0.70, 4.0, 1.0e7);
const dkq = wag.deltaKQ(0.6, 1.0, 0.70, 4.0, 1.0e7);

// Validate inputs are within the B-series envelope.
try wag.validate(0.6, 1.0, 0.70, 4, 1.0e7);
```

## Validity envelope

| Parameter | Range |
|---|---|
| Z (blades) | 2 to 7 |
| P/D | 0.5 to 1.4 |
| A_E/A_0 | 0.30 to 1.05 |
| J | 0 to 1.5 |
| Reynolds Rn | 2.0e6 to 2.0e9 (Reynolds correction polynomial valid range) |

Outside these ranges, the polynomial is an extrapolation. `validate`
returns an explicit error.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- Oosterveld, M.W.C. and van Oossanen, P. (1975), "Further computer-
  analyzed data of the Wageningen B-screw series," International
  Shipbuilding Progress, Vol. 22, No. 251.
- Bernitsas, M.M., Ray, D., and Kinley, P. (1981), "K_T, K_Q and
  Efficiency Curves for the Wageningen B-Series Propellers," University
  of Michigan Department of Naval Architecture and Marine Engineering,
  Report No. 237.
- Carlton, J. (2018), *Marine Propellers and Propulsion*, 4th ed.,
  Butterworth-Heinemann.
- Codex cross-references at
  `~/codex/concepts/wageningen-b-series-propeller-coefficients.md` and
  `~/codex/sources/naome_data_substrate_deep.md` Section 2A.

## License

AGPL-3.0-or-later. See `LICENSE`.
