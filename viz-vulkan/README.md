# yard-viz-vulkan

Proof level: `unit-tested` (headless SVG bridge)

Scene-graph renderer for yard workflows. Phase 2a: JSON scene → SVG via
`yard-viz` (no GPU). Phase 2b: Vulkan draw stub (`-Dvulkan=enabled`).

## What it does

- `scene` — parse hull scene JSON (`kind`, `length_m`, `beam_m`, `draft_m`).
- `headless.renderSceneSvg` — deterministic SVG via `hull_profile_svg`.
- `render-scene` CLI — `zig build render-scene -- scene.json -o out.svg`.
- `vulkan_draw` (optional) — compile-time stub for future GPU path.

## What it is not

- Not photo-real ocean rendering.
- Not a class-society regulatory visualization standard.
- Vulkan draw is not linked in default builds (headless only).

## Build and test

```sh
cd viz-vulkan && zig build test
zig build render-scene -- ../examples/scene-kcs.json -o kcs.svg
```

License: Apache-2.0.