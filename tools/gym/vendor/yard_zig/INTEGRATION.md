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

`zig_gym/` mirrors **Python** `hull.evaluate_l0` + `resistance_l1.estimate_resistance`
(Holtrop-**simplified** exploratory ranking), not the full yard HM 1984 API.

## Next FFI steps (not done here)

1. Add Zig module deps in `zig_gym/build.zig`:
   ```zig
   // addModule("yard_resistance", .{ .root_source_file = b.path("../vendor/yard_zig/resistance/src/root.zig") });
   // addModule("yard_hydro", .{ .root_source_file = b.path("../vendor/yard_zig/hydro/src/root.zig") });
   ```
2. Map `Hull` → `holtrop.HullParticulars` (needs Cp, Cm, S, LCB abs, optional bulb/transom).
3. Prefer `hydro.box_barge` GM for Cb≈1 barge cases; keep Python-parity `gm0` for high-Cb box L0.
4. Export `export fn yard_l0(...)` / `yard_l1_hm1984(...)` C ABI + build shared lib for ctypes.
5. Keep subprocess JSON bridge as fallback (`yard_sea_v0.zig_bridge`).

Do **not** push the yard monorepo from this box.
