# Ship-D Dataverse ingest result

- Written: 2026-09-10 16:54 ET
- Dataset: Harvard Dataverse **doi:10.7910/DVN/MMGAUS** (Ship-D)
- Authors: Bagazinski, Noah & Ahmed, Faez (MIT)
- License: **CC0 1.0**

## Vectors (search parents)

| Item | Value |
|------|-------|
| Path | `yard_sea_v0/data/InputVectors_30k.npy` |
| Source | GitHub `noahbagz/ShipD` mirror of Constrained Randomized sets |
| Shape | **30000 × 45** (float64) |
| Size | **10,800,128 bytes** (~10.8 MB) |
| `shipd_surface` available | True |

CLI:

```sh
python -m yard_sea_v0 ingest-shipd
python -m yard_sea_v0 run-search --corpus 5 --steps 40 --out out/corpus_gallery
```

## Dataverse API probe

| Item | Value |
|------|-------|
| Files listed | **249** |
| Total bytes on Dataverse | **317,682,837** (~318 MB) |
| Files ≥ 200 MB | **0** (none) |
| License | CC0 1.0 |

Largest remote files (not all downloaded):

- Diffusion_Aug_Set_1/GeometricMeasures/Cw.tab — 29.3 MB
- Diffusion_Aug_Set_1/Input_Vectors.tab — 25.8 MB
- Diffusion_Aug_Set_1/GeometricMeasures/Rw_Output.npy — 10.7 MB

## Downloaded locally under `yard_sea_v0/data/dataverse/`

Total mirrored metadata/metrics: **6,150,551 bytes** (14 files).

| Bytes | Path |
|------:|------|
| 3,829 | `dataverse/Input_Vectors_SampleHulls.csv` |
| 201,290 | `dataverse/dataset_api.json` |
| 133,891 | `dataverse/docs/HullParameterizationOverview.pdf` |
| 129,467 | `dataverse/docs/HullParameterization_ConstraintsOverview.pdf` |
| 1,187 | `dataverse/docs/PCGen.py` |
| 1,068 | `dataverse/docs/STLGen.py` |
| 67,518 | `dataverse/files_catalog.json` |
| 168,929 | `dataverse/metrics/CRS1_GaussianCurvature.tab` |
| 918,691 | `dataverse/metrics/CRS1_MaxBox.tab` |
| 2,560,128 | `dataverse/metrics/CRS1_Rw_Output1.npy` |
| 1,952,378 | `dataverse/metrics/CRS1_Volume.tab` |
| 4,083 | `dataverse/stats/Constrained_Randomized_Set_1_DatasetStats.tab` |
| 4,060 | `dataverse/stats/Constrained_Randomized_Set_2_DatasetStats.tab` |
| 4,032 | `dataverse/stats/Constrained_Randomized_Set_3_DatasetStats.tab` |

## Skipped

- **Mesh archives:** none present as discrete zip/tar mesh dumps in the 249-file listing; meshes are generated via `STLGen.py` / `HullParameterization.gen_stl` (Blender `.blend` lighting files ~0.8–0.9 MB each also skipped).
- **Files ≥ 200 MB:** none on Dataverse for this DOI.
- **Not mirrored:** full GeometricMeasures for CRS2/CRS3 and both Diffusion_Aug sets (Volume/Cw/Ixx/Iyy/LCB/… tabs), Diffusion Input_Vectors.tab/.npy beyond CRS1 Rw/Volume/MaxBox/GaussianCurvature sample, histogram PNGs.
- **Intentional:** keep corpus usable for search parents via 30k npy; avoid bulk ~300 MB full mirror.

## Code added

- `yard_sea_v0/corpus.py` — load/iterate/sample parents; optional `shipd_surface` constraint filter; Dataverse probe + ingest manifest
- CLI: `ingest-shipd`, `run-search --corpus N`
- Tests: `tests/test_corpus.py`
- Citation/license: `yard_sea_v0/data/README.md`

## Verification

- `InputVectors_30k.npy` loads as (30000, 45)
- `run-search --corpus 3` produced improved children (smoke)
- pytest: corpus + full suite green at time of writing

