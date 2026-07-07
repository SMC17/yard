# yard-viz

Deterministic visualization primitives for yard workflows.

## Phase 1 (now)

- `gz_svg.zig` — GZ stability curve → SVG (oracle-verified, no GPU deps)
- `render_cli.zig` — CLI export from JSON

## Phase 2 (viz-vulkan/)

Vulkan 3D hull + pressure/wave overlays. See `../viz-vulkan/ROADMAP.md`.

## Usage

```sh
cd viz && zig build test
zig build render-gz -- oracle_output.json -o curve.svg
```

Python mirror (dataset pipeline): `tools/viz/render_gz_svg.py`