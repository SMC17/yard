# Yard-Sea-v0 data (Ship-D)

## Citation

Bagazinski, Noah J., and Faez Ahmed. 2023. “Ship-D: Ship Hull Dataset for Design
Optimization Using Machine Learning.” In *International Design Engineering Technical
Conferences and Computers and Information in Engineering Conference*, vol. 87301,
V03AT03A028. ASME. https://doi.org/10.1115/DETC2023-117003

Related: Bagazinski, Noah J., and Faez Ahmed. 2023. “ShipGen: A Diffusion Model for
Parametric Ship Hull Generation with Multiple Objectives and Constraints.” *Journal of
Marine Science and Engineering* 11(12): 2215. https://doi.org/10.3390/jmse11122215

## Dataset

- **Harvard Dataverse:** https://doi.org/10.7910/DVN/MMGAUS (CC0 1.0)
- **GitHub sample / vectors mirror:** https://github.com/noahbagz/ShipD

## Local files

| Path | Source | Notes |
|------|--------|-------|
| `InputVectors_30k.npy` | GitHub `noahbagz/ShipD` | `(30000, 45)` float64; three Constrained Randomized sets |
| `shipd_sample_vectors.csv` | Ship-D sample hulls | Small CSV for unit tests / `--shipd` |
| `dataverse/` | Harvard Dataverse API downloads | Stats, docs PDFs, CRS1 metrics subset; see `files_catalog.json` |

## License

Dataverse release license: **CC0 1.0** (public domain dedication). Cite Bagazinski & Ahmed
when using Ship-D vectors or metrics. Yard-Sea-v0 does not claim ownership of Ship-D.

## Skipped (not mirrored locally)

Large GeometricMeasures tabs for Diffusion_Aug sets, full CRS2/CRS3 metrics, Blender
`.blend` lighting files, and mesh generation (use upstream `STLGen.py` / CadQuery path).
No discrete mesh archives ≥200 MB appeared in the Dataverse file listing (~318 MB total
across 249 files; largest single file ~29 MB `Cw.tab`).
