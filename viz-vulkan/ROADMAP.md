# viz-vulkan — High-Fidelity Rendering Layer

**Status:** Skeleton / Phase 2  
**Proof level:** Not yet implemented

## Architecture Split

```
┌─────────────────────┐     scene_graph + physics_state (JSON)
│  Fine-tuned model   │ ──────────────────────────────────────►
│  or agent layer     │
└─────────────────────┘
                              ┌─────────────────────┐
                              │  yard-viz-vulkan    │
                              │  Zig + Vulkan       │
                              │  deterministic draw │
                              └─────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
              2D GZ curves        3D hull mesh      stress/wave overlay
```

The model outputs **structured scene graphs**. The renderer draws them deterministically.
Numbers always come from yard oracle/Zig — never from the model.

## Phase 2 Deliverables

1. **2D curve renderer** (Vulkan line/polygon) — parity with `viz/gz_svg.zig`
2. **Box-barge 3D mesh** from principal particulars
3. **Waterplane + heel animation** for stability review
4. **Export:** PNG sequence, glTF for AR/VR review

## Phase 3 Deliverables

- Pressure distribution heatmap from hydro output
- Wave field overlay from strip-theory / bem reduced-order
- Real-time capable path (<16ms frame for ops dashboards)

## Dependencies (planned)

- Zig 0.16+
- Vulkan 1.2+ (GTX 1650 OK via Vulkan; CUDA not required for render)
- Optional: FMI coupling for external CFD/FEA textures

## Non-Goals (Phase 2)

- Class-society regulatory rendering standards
- Photo-real ocean simulation
- Model-in-the-loop physics (oracle only)