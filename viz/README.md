# yard-viz

Deterministic visualization primitives for yard workflows.

Proof level: `unit-tested` (oracle-verified SVG export; no GPU deps)

## What it does

- **`gz_svg`** — GZ stability curve → SVG with optional IS Code threshold
  overlays.
- **`pareto_svg`** — multi-objective Pareto front scatter (power vs heave, GM
  labels) for spiral optimization campaigns.
- **`hull_profile_svg`** — 2D hull profile (waterline + midship section) for
  box-barge and Wigley parametric forms.
- **`render_cli`** — CLI export from JSON oracle output.

## What it is not

Not interactive 3D rendering. Vulkan hull and pressure/wave overlays live in
`../viz-vulkan/` (Phase 2). Not a charting library, GIS viewer, or
classification-society drawing package. SVG output is deterministic and
file-based — not a live dashboard.

## Build and test

```sh
cd viz && zig build test
zig build render-gz -- oracle_output.json -o curve.svg
```

Python mirror (dataset pipeline): `tools/viz/render_gz_svg.py`

## License

Apache-2.0. See `LICENSE`.