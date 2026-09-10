# Ship-D upstream (vendored)

Source: https://github.com/noahbagz/ShipD (Noah Bagazinski / MIT DeCoDe)

Vendored for Yard-Sea-v0 local constraint eval + STL generation:

- `HullParameterization.py` — `Hull_Parameterization`, `input_Constraints` (49 algebraic), `gen_stl`
- `STLGen.py`, `MaxBox.py`, `Gaussian_Curvature.py`, `ModifiedMichellCw.py` — helpers (optional)
- `X_LABELS.npy` — 45 parameter names

## Local patches (documented)

1. **NumPy 2.x `np.trapz`**: shim to `np.trapezoid` when missing.
2. **NumPy 2.x scalar assign**: `halfBeam_BB(...)[0]` in `gen_waterline_bow_BB` (upstream omitted `[0]`).

Not a full git submodule — parent agents refresh from upstream as needed.

Deps: `numpy`, `numpy-stl`, `matplotlib` (imported at module load).
