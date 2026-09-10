# Zig L0/L1 mirror — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Goal:** Install Zig; wire Yard-Sea-v0 Zig L0/L1 toward resistance/hydro FFI.

## Success criteria

| Criterion | Status |
|-----------|--------|
| Zig toolchain installed | **PASS** — Zig **0.15.2** at `/usr/local/bin/zig` → `/opt/zig/0.15.2/zig` |
| `zig_gym` builds | **PASS** — `cd zig_gym && zig build` → `zig-out/bin/yard_sea_zig` |
| `zig build test` | **PASS** — L0 feasibility + GM + L1 Ct smoke |
| Holtrop-simplified / GM parity | **PASS** — Zig mirrors Python `hull` + `resistance_l1` |
| Python bridge | **PASS** — `yard_sea_v0/zig_bridge.py` (subprocess JSON; ctypes path noted) |
| Python ↔ Zig L0 tests | **PASS** — `tests/test_zig_bridge.py` (5 tests) |
| Vendor yard resistance/hydro | **PASS** — Contents API → `vendor/yard_zig/` + `INTEGRATION.md` |
| No GitHub push of yard monorepo | **PASS** — read-only API fetch only |

## Toolchain

```
zig version → 0.15.2
Install: tarball https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz → /opt/zig/0.15.2
```

## Artifacts

- `zig_gym/root.zig` — L0 (`evaluate_l0` / GM0) + L1 (`estimate_resistance` Holtrop-simplified)
- `zig_gym/main.zig` — JSON CLI for bridge
- `zig_gym/build.zig` — exe `yard_sea_zig` + test step
- `yard_sea_v0/zig_bridge.py` — `call_zig` / `evaluate_l0_zig` / `estimate_resistance_zig`
- `tests/test_zig_bridge.py` — default + bad-Cb + L1 + both-mode + perturbed hull
- `vendor/yard_zig/{resistance,hydro}/` — vendored snippets from `SMC17/yard`
- `vendor/yard_zig/INTEGRATION.md` — FFI path to full HM1984 / box_barge

## Default HullState parity (spot check)

| Metric | Python | Zig |
|--------|--------|-----|
| feasible | true | true |
| gm0_m | 4.055555555555555 | 4.055555555556 |
| volume_m3 | 14400 | 14400 |
| Ct | 0.0025105906077265722 | 0.002510590608 |
| Rt_N | ~255105.631 | ~255105.631 |

## Integration path (next)

1. Wire `vendor/yard_zig/resistance` + `hydro` as Zig modules (see INTEGRATION.md).
2. Map particulars → `holtrop.HullParticulars` for full HM 1984 (vs current simplified L1).
3. Optional: `export` C ABI + shared lib for ctypes; keep subprocess bridge as fallback.
4. Do not clone/push full private yard monorepo from this environment.

## Notes / limits

- Zig gym L1 matches **Python exploratory** Holtrop-simplified, **not** yet the vendored yard `holtrop.zig` 1984 reanalysis.
- Hydro `root.zig` imports `simpson.zig` (fetched); full hydro package not built as a dependency of zig_gym yet.
- PAT used only for **read** Contents API fetches into `vendor/`.
