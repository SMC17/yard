# yard monorepo Zig → Yard-Sea-v0 integration path

Vendored **read-only** snippets from private `SMC17/yard` via GitHub Contents API
(no full clone). Modules:

| Path | Role |
|------|------|
| `resistance/src/ittc57.zig` | ITTC-57 Cf |
| `resistance/src/holtrop.zig` | HM 1984 form factor + wave resistance |
| `resistance/src/holtrop_extended.zig` | Full c1…c16 / appendage / CA |
| `hydro/src/box_barge.zig` | Closed-form KB/BMT/KMT for box barge |
| `hydro/src/wigley.zig` | Wigley parametric hydrostatics |
| `hydro/src/integrate.zig` / `simpson.zig` | Ordinate integrators |

## Current state (zig_gym)

`zig_gym/` still mirrors Python Holtrop-**simplified** for L0/L1 parity, and now
also wires **vendored HM 1984** via package import:

```zig
// zig_gym/build.zig
const yard_resistance = b.createModule(.{
    .root_source_file = b.path("../vendor/yard_zig/resistance/src/root.zig"),
    ...
});
```

CLI modes: `l0` | `l1` | `l1_hm1984` | `both` | `both_hm1984`

Python: `estimate_resistance_zig(..., fidelity='simplified'|'hm1984')`
Teacher: `yard_sea_v0.teachers.zig_l1.estimate_l1`

## HullState → holtrop.HullParticulars mapping

| Field | Source |
|-------|--------|
| L, B, T | HullState direct |
| C_B | HullState.Cb |
| displacement_vol | L·B·T·Cb |
| S | wetted_approx() |
| lcb_pct | lcb_frac × 100 (Holtrop %L, fwd+) |
| C_M | **missing** → default 0.98 |
| C_P | **missing** → C_B / C_M (clamped) |
| C_WP | **missing** → Denny (1+2·C_B)/3 |
| c_stern | **missing** → 0 (normal); simplified path used ≈10 |
| bulb / transom | **missing** → null (no R_B / c5 correction) |

## Remaining FFI steps

1. Prefer `hydro.box_barge` GM for Cb≈1 barge cases; keep Python-parity `gm0` for high-Cb box L0.
2. Optional: `export fn yard_l1_hm1984(...)` C ABI + shared lib for ctypes.
3. Keep subprocess JSON bridge as primary (`yard_sea_v0.zig_bridge`).

Do **not** push the yard monorepo from this box.
