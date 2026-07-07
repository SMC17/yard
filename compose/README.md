# yard-compose

Multi-module workflows that wire yard primitives into end-to-end pipelines.

**Proof level:** `unit-tested` (inherits weakest link in chain).

## Workflows

| Module | Primitives | Output |
|--------|------------|--------|
| `box_barge` | hydro + stability | Hydrostatics, GM, GZ curve, IMO IS Code 2.2 |

## Build

```sh
zig build test
```

## Extension

Add new workflows as `src/<name>.zig` and re-export from `root.zig`. Each workflow
must declare its proof level, validity envelope, and assumption flags.

License: Apache-2.0.