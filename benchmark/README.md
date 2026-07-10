# yard-benchmark-zig

Proof level: `unit-tested` (harness); `cross_validated` (Holtrop / ITTC chain);
`benchmark_hull` (tank ingest)

Standard-hull validation harness for the yard naval simulation suite.

## What it does

- **`hulls`** — published fixtures: Wigley, KCS, KVLCC2, Series-60 Cb=0.60 with
  Holtrop particulars, design speed, and model length (λ ≈ 0.05 default).
- **`harness.runAll`** — 18 regression cases with explicit tolerances: Wigley
  closed-form hydrostatics (C_B, KB/T, BM_T); Holtrop total resistance and
  design Fn for KCS, KVLCC2, Series-60; Froude kinematic closure per hull;
  similarity vs ITTC-78 P_E agreement on KCS; tank C_T extrapolation on KCS
  and KVLCC2.
- **`tank_data`** — representative low-Fn model-test C_T series (Fn, C_T) for
  KCS and KVLCC2.
- **`tank_extrapolate`** — Prohaska (1+k) from tank points and ITTC-78
  extrapolation at design Fn; reports P_E and relative error.

## What it is not

Not a towing-tank database or class-society correlation service. Embedded tank
points are workshop-scale regression data for harness checks — not certified
model-test certificates. Not a substitute for project-specific model tests or
full-scale trials.

## Build and test

```
zig build test --summary all
```

## License

Apache-2.0. See `LICENSE`.