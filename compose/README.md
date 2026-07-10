# yard-compose

Multi-module workflows that wire yard primitives into end-to-end pipelines.

**Proof level:** `unit-tested` (inherits weakest link in chain).

## What it does

- **`box_barge`** — box-barge hydrostatics → GZ curve → IMO IS Code 2008 Part A
  2.2 intact stability.
- **`cargo_resistance`** — Holtrop-Mennen 1984 total resistance + ITTC-57 C_F
  for a representative single-screw cargo hull.
- **`vessel_assessment`** — combines `box_barge` stability with
  `cargo_resistance` into one preliminary assessment.
- **`seakeeping_assessment`** — ITTC-PM spectrum → strip-theory heave RAO →
  response statistics and optional Fossen RK4 time-domain check.
- **`damage_stability`** — lost-buoyancy box-barge flooding → residual GM and
  IS Code evaluation.
- **`time_domain_sim`** — Fossen 6-DOF RK4 with quasi-steady Holtrop surge
  drag.
- **`irregular_wave_sim`** — multi-sine ITTC-PM irregular-wave forcing on
  Fossen RK4 with optional surge drag.
- **`dp_station_keeping`** — thruster allocation + proportional position hold
  under wave disturbance.
- **`coupled_dp_waves`** — DP station-keeping under irregular-wave sway
  forcing.
- **`pareto_report`** — spiral optimizer Pareto front → SVG via `yard-viz`.
- **`design_spiral`** — thin wrapper over `yard-spiral` with naval-arch
  validity flags and objective scoring.

## What it is not

Not a ship-design suite or CAD tool. Workflows are composition glue over
substrate primitives; proof level inherits the weakest module in each chain.
Not regulatory certification, class society submission, or production voyage
planning. Does not replace project-specific analysis by a qualified naval
architect.

## Build and test

```sh
zig build test
```

## Extension

Add new workflows as `src/<name>.zig` and re-export from `root.zig`. Each
workflow must declare its proof level, validity envelope, and assumption flags.

## License

Apache-2.0. See `LICENSE`.