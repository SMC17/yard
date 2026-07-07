# Architecture Deep Dive

## Design Principles

1. **One thing well** — Each of 69 modules implements a single verifiable primitive.
2. **Explicit proof levels** — Never overclaim validation depth.
3. **Oracle-first** — Zig code is ground truth; Python oracle mirrors for dataset scale.
4. **Composition over god-modules** — `compose/` wires primitives; operators extend upward.

## Layer Interaction

```mermaid
graph TB
    subgraph L1["Layer 1: Primitives"]
        direction LR
        H[hydro]
        S[stability]
        R[resistance]
    end

    subgraph L2["Layer 2: Composition"]
        NA[naval-arch/types]
        C[compose/box_barge]
        E[examples/]
    end

    subgraph L3["Layer 3: Intelligence"]
        O[tools/oracle]
        D[tools/dataset]
        EV[tools/eval]
    end

    H --> C
    S --> C
    NA --> C
    C --> E
    S --> O
    H --> O
    O --> D
    D --> EV
```

## Shared Type Contract

`naval-arch/src/types.zig` defines the interchange schema:

| Type | Used by | Purpose |
|------|---------|---------|
| `PrincipalParticulars` | All hull workflows | L, B, T |
| `LoadingCondition` | Stability workflows | KG + tanks |
| `Hydrostatics` | Hydro → compose | V, KB, BM, KM |
| `StabilitySummary` | Stability → compose | GM, GG', flags |
| `IsCodeResult` | Regulatory overlay | Six criteria + overall |
| `ValidityFlags` | All workflows | Assumption tracking |

Primitive modules do **not** import `naval-arch`. Only `compose/` and `examples/` do.
This preserves independent adoption of any single primitive.

## Extension Pattern (Goldman Layer)

```mermaid
flowchart LR
    A[Your workflow] --> B[compose/ or direct primitive import]
    B --> C[naval-arch types]
    C --> D[JSON / Python / Agent I/O]
    D --> E[Fleet dashboard / Class report / Port ops]
```

Recommended extension path:

1. Fork or add `compose/src/your_workflow.zig`
2. Import only the primitives you need
3. Emit structured output matching `tools/dataset/schema.json`
4. Add eval cases to `tools/eval/`
5. Publish your layer; yard substrate stays stable

## CI Topology

```
push → test-core (hydro, stability, naval-arch, compose, example)
     → test-all  (69 modules, parallel matrix)
     → oracle self-test
     → dataset integrity check
```

See `.github/workflows/ci.yml`.