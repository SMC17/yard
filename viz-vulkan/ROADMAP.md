# viz-vulkan - native simulation viewer roadmap

## Landed foundation

Proof level: deterministic reference path `unit-tested`; optional native Vulkan
bootstrap `integration-tested` when the Vulkan test gate passes on a host.

- versioned fleet scene shape with dynamic 6-axis vessel poses
- legacy single-hull scene compatibility
- deterministic 3D wireframe fleet frame and golden SHA-256
- Vulkan physical-device and queue-family discovery
- Vulkan command-pool/buffer execution, synchronization, host-visible readback
- GPU/readback frame parity against the CPU reference
- CLI fixture for multi-vessel formation frames

## Next graphics gate

1. Create a Vulkan graphics pipeline with explicit SPIR-V shader provenance.
2. Upload hull vertex/index buffers rather than compositing reference lines.
3. Render to an offscreen color/depth image and preserve deterministic readback.
4. Add camera matrices, depth ordering, and pressure/wave scalar overlays.
5. Gate every frame on nonblank pixels, golden fixture tolerance, and device-loss handling.

## Native viewer gate

1. Add a Wayland/XCB surface abstraction and `VK_KHR_swapchain` negotiation.
2. Run a fixed-step simulation clock independent of presentation cadence.
3. Consume immutable fleet snapshots from the telemetry/replay boundary.
4. Add orbit/pan/zoom controls, vessel selection, trails, and formation errors.
5. Record frames with simulation tick, scene hash, and replay-chain head.

## Fidelity expansion

- pressure and structural-margin heatmaps
- directional wave field and encounter-frequency overlays
- heel, trim, sinkage, rudder, sail, and thruster state animation
- bathymetry, routes, gates, and mission geometry
- glTF export only after coordinate, unit, and provenance contracts are frozen

## Proof gates before performance claims

- fixed public scene corpus and output hashes
- Vulkan validation-layer clean run
- offscreen/native parity policy with documented tolerances
- frame-time benchmark with resolution, vessel count, GPU class, and command
- device-loss and missing-loader negative tests
- at least one replay-driven multi-vessel integration test

Photo-real rendering and regulatory display approval remain out of scope until
the deterministic engineering viewer is complete and measured.
