# yard-viz-vulkan

Proof levels:

- deterministic 3D fleet reference frame: `unit-tested`
- native Vulkan device/queue, command-buffer fill, synchronization, and readback: `integration-tested` when `-Dvulkan=true` is run on a Vulkan host
- swapchain presentation and GPU geometry pipeline: `scaffold` / not implemented

`yard-viz-vulkan` is the render boundary for Yard simulation state. It accepts a
fleet scene with vessel dimensions and six-axis poses, renders a deterministic
3D wireframe frame for CI/replays, and optionally proves the native Vulkan path
by filling and reading back the frame through a real Vulkan queue.

## Current rendering contract

- `scene` parses the legacy single-hull JSON form and the multi-vessel fleet form.
- `frame` projects dynamic vessel poses into a stable orthographic fleet view.
- `render-frame` emits a deterministic 960x540 PPM without a GPU.
- `headless.renderSceneSvg` retains the original single-hull SVG bridge.
- `native-frame` initializes Vulkan, selects a capable queue family, performs a
  command-buffer fill/readback, composites the same deterministic 3D geometry,
  and emits a PPM.

The geometry overlay is currently the shared CPU reference rasterizer. Vulkan
owns device discovery, queue execution, synchronization, and framebuffer
readback. A graphics pipeline and swapchain are the next gate; this module does
not claim them yet.

## Scene input

```json
{
  "title": "Formation",
  "simulation_time_s": 42.0,
  "vessels": [
    {
      "id": "lead",
      "hull": {
        "kind": "wigley",
        "length_m": 120.0,
        "beam_m": 18.0,
        "draft_m": 6.0
      },
      "pose": {
        "north_m": 45.0,
        "east_m": 0.0,
        "heave_m": 0.0,
        "roll_rad": 0.06,
        "pitch_rad": -0.02,
        "yaw_rad": 0.18
      }
    }
  ]
}
```

`kind` is currently `wigley` or `box_barge`. Dimensions must be positive, beam
cannot exceed length, draft cannot exceed beam, and all pose values must be
finite.

## Build and verify

```sh
cd viz-vulkan
zig build test
zig build render-frame -- scenes/formation.json -o formation.ppm
zig build test -Dvulkan=true
zig build native-frame -Dvulkan=true -- \
  scenes/formation.json -o formation-native.ppm --width 960 --height 540
cmp formation.ppm formation-native.ppm
```

The package build supplies the conventional Linux Vulkan library paths to its
run steps because a Zig toolchain may be Nix-linked while GPU
ICDs are system-installed. Standalone installed binaries still need a normal
Vulkan loader/ICD environment. Override a different distribution layout with
`-Dvulkan-library-path=/usr/lib64` (or the appropriate colon-separated path).

The golden 320x180 reference frame is SHA-256
`96ef989f3e952a08e430a549ecf0aa05ed1396d2256f6a2bea53e387b31fc758`.

## Non-goals at this proof level

- no claim of photoreal ocean rendering
- no class-society visualization standard
- no GPU hull rasterization yet
- no window, input loop, swapchain, animation clock, or camera controls yet
- no performance claim until a graphics pipeline and frame benchmark exist

License: Apache-2.0.
