"""Ship-D 30k corpus loader for Yard-Sea-v0 search parents.

Primary vectors: ``InputVectors_30k.npy`` (GitHub ShipD mirror of the three
Constrained Randomized sets on Harvard Dataverse doi:10.7910/DVN/MMGAUS).

Optional: if ``yard_sea_v0.shipd_surface`` is importable, algebraic Ship-D
constraints (49) can filter parents. Dataset hulls already satisfy them;
filtering is mainly useful for custom / mutated vectors.
"""

from __future__ import annotations

import json
import shutil
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, Sequence

import numpy as np

from .hull import HullState, evaluate_l0
from .shipd import ShipDVector, project_to_hull

DATA_DIR = Path(__file__).resolve().parent / "data"
DEFAULT_VECTORS_PATH = DATA_DIR / "InputVectors_30k.npy"
GITHUB_VECTORS_URL = (
    "https://raw.githubusercontent.com/noahbagz/ShipD/main/InputVectors_30k.npy"
)
DATAVERSE_DOI = "doi:10.7910/DVN/MMGAUS"
DATAVERSE_API = (
    "https://dataverse.harvard.edu/api/datasets/:persistentId/"
    f"?persistentId={DATAVERSE_DOI}"
)
DATAVERSE_DIR = DATA_DIR / "dataverse"

_SHIPD_SURFACE = None
_SHIPD_SURFACE_TRIED = False


def _try_shipd_surface():
    """Lazy optional import of shipd_surface constraint helper."""
    global _SHIPD_SURFACE, _SHIPD_SURFACE_TRIED
    if _SHIPD_SURFACE_TRIED:
        return _SHIPD_SURFACE
    _SHIPD_SURFACE_TRIED = True
    try:
        from . import shipd_surface as ss  # type: ignore

        _SHIPD_SURFACE = ss
    except Exception:  # noqa: BLE001 — optional dep / incomplete surface
        _SHIPD_SURFACE = None
    return _SHIPD_SURFACE


@dataclass(frozen=True)
class CorpusInfo:
    path: Path
    n_vectors: int
    n_dims: int
    dtype: str
    bytes: int
    shipd_surface_available: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "path": str(self.path),
            "n_vectors": self.n_vectors,
            "n_dims": self.n_dims,
            "dtype": self.dtype,
            "bytes": self.bytes,
            "shipd_surface_available": self.shipd_surface_available,
            "doi": DATAVERSE_DOI,
        }


def ensure_input_vectors(
    dest: Path | None = None,
    *,
    url: str = GITHUB_VECTORS_URL,
) -> Path:
    """Ensure InputVectors_30k.npy exists under data/; download from GitHub if missing."""
    dest = Path(dest) if dest is not None else DEFAULT_VECTORS_PATH
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_file() and dest.stat().st_size > 1_000_000:
        return dest
    # Prefer vendor copy if present
    for candidate in (
        DATA_DIR.parent.parent / "vendor" / "shipd" / "InputVectors_30k.npy",
        DATA_DIR.parent.parent / "vendor" / "shipd_upstream" / "InputVectors_30k.npy",
    ):
        if candidate.is_file() and candidate.stat().st_size > 1_000_000:
            if not dest.exists():
                try:
                    dest.symlink_to(candidate.resolve())
                except OSError:
                    shutil.copy2(candidate, dest)
            return dest
    with urllib.request.urlopen(url, timeout=120) as resp:
        dest.write_bytes(resp.read())
    return dest


def load_input_vectors(path: Path | None = None) -> np.ndarray:
    """Load (N, 45) float array of Ship-D input vectors."""
    path = Path(path) if path is not None else ensure_input_vectors()
    arr = np.load(path)
    if arr.ndim != 2 or arr.shape[1] != 45:
        raise ValueError(f"expected (N, 45) vectors, got shape {arr.shape}")
    return np.asarray(arr, dtype=np.float64)


def corpus_info(path: Path | None = None) -> CorpusInfo:
    path = Path(path) if path is not None else ensure_input_vectors()
    arr = load_input_vectors(path)
    return CorpusInfo(
        path=path,
        n_vectors=int(arr.shape[0]),
        n_dims=int(arr.shape[1]),
        dtype=str(arr.dtype),
        bytes=int(path.stat().st_size),
        shipd_surface_available=_try_shipd_surface() is not None,
    )


def iter_vectors(
    path: Path | None = None,
    *,
    indices: Sequence[int] | None = None,
) -> Iterator[tuple[int, ShipDVector]]:
    """Yield (index, ShipDVector) over the corpus (or a subset of indices)."""
    arr = load_input_vectors(path)
    if indices is None:
        for i in range(arr.shape[0]):
            yield i, ShipDVector.from_sequence(arr[i])
    else:
        for i in indices:
            yield int(i), ShipDVector.from_sequence(arr[int(i)])


def vector_satisfies_shipd_constraints(vec: ShipDVector | Sequence[float]) -> bool | None:
    """Return True/False if shipd_surface can evaluate; None if unavailable."""
    ss = _try_shipd_surface()
    if ss is None:
        return None
    values = vec.values if isinstance(vec, ShipDVector) else tuple(float(x) for x in vec)
    if hasattr(ss, "evaluate_constraints"):
        return bool(ss.evaluate_constraints(values).feasible)
    if hasattr(ss, "satisfies_constraints"):
        return bool(ss.satisfies_constraints(values))
    if hasattr(ss, "input_constraints"):
        c = np.asarray(ss.input_constraints(values), dtype=np.float64)
        return bool(np.sum(c > 0) == 0)
    if hasattr(ss, "check_constraints"):
        return bool(ss.check_constraints(values))
    return None


def sample_parent_indices(
    n: int,
    *,
    seed: int = 0,
    path: Path | None = None,
    filter_constraints: bool = True,
    filter_l0: bool = True,
    max_tries: int | None = None,
) -> list[int]:
    """Sample up to ``n`` corpus indices suitable as search parents."""
    arr = load_input_vectors(path)
    n_total = arr.shape[0]
    rng = np.random.default_rng(seed)
    order = rng.permutation(n_total)
    limit = max_tries if max_tries is not None else min(n_total, max(n * 50, 500))
    use_surface = filter_constraints and _try_shipd_surface() is not None
    chosen: list[int] = []
    for i in order[:limit]:
        vec = ShipDVector.from_sequence(arr[int(i)])
        if use_surface:
            ok = vector_satisfies_shipd_constraints(vec)
            if ok is False:
                continue
        if filter_l0:
            hull = project_to_hull(vec)
            if not evaluate_l0(hull).feasible:
                continue
        chosen.append(int(i))
        if len(chosen) >= n:
            break
    return chosen


def sample_parents(
    n: int,
    *,
    seed: int = 0,
    path: Path | None = None,
    filter_constraints: bool = True,
    filter_l0: bool = True,
) -> list[HullState]:
    """Sample projected HullState parents from the 30k corpus."""
    idxs = sample_parent_indices(
        n,
        seed=seed,
        path=path,
        filter_constraints=filter_constraints,
        filter_l0=filter_l0,
    )
    arr = load_input_vectors(path)
    parents = [project_to_hull(arr[i]) for i in idxs]
    if len(parents) < n:
        # Pad with default exploratory hulls if corpus filter is too strict.
        from .gallery import default_parents

        parents.extend(default_parents(n - len(parents), seed=seed + 17))
    return parents[:n]


def probe_dataverse(timeout: float = 60.0) -> dict[str, Any]:
    """Query Harvard Dataverse API for Ship-D file listing (no bulk download)."""
    req = urllib.request.Request(
        DATAVERSE_API,
        headers={"User-Agent": "Yard-Sea-v0/0.1 (research; +https://github.com/)"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        payload = json.loads(resp.read().decode())
    files = payload["data"]["latestVersion"]["files"]
    rows = []
    for f in files:
        df = f["dataFile"]
        rows.append(
            {
                "id": df.get("id"),
                "filename": df.get("filename"),
                "directoryLabel": f.get("directoryLabel"),
                "filesize": df.get("filesize"),
                "contentType": df.get("contentType"),
            }
        )
    total = sum(r["filesize"] or 0 for r in rows)
    large = [r for r in rows if (r["filesize"] or 0) >= 200_000_000]
    license_info = payload["data"]["latestVersion"].get("license")
    return {
        "doi": DATAVERSE_DOI,
        "n_files": len(rows),
        "total_bytes": total,
        "license": license_info,
        "n_files_ge_200mb": len(large),
        "files_ge_200mb": large,
        "files": rows,
    }


def ingest_shipd(
    *,
    out_manifest: Path | None = None,
    download_vectors: bool = True,
) -> dict[str, Any]:
    """Ensure local vectors + summarize Dataverse probe / local dataverse mirror."""
    path = ensure_input_vectors() if download_vectors else DEFAULT_VECTORS_PATH
    info = corpus_info(path)
    probe: dict[str, Any] | None = None
    probe_error: str | None = None
    try:
        probe = probe_dataverse()
    except Exception as exc:  # noqa: BLE001
        probe_error = str(exc)

    local_dv: list[dict[str, Any]] = []
    if DATAVERSE_DIR.is_dir():
        for p in sorted(DATAVERSE_DIR.rglob("*")):
            if p.is_file():
                local_dv.append({"path": str(p.relative_to(DATA_DIR)), "bytes": p.stat().st_size})

    result = {
        "corpus": info.to_dict(),
        "dataverse_probe": (
            {
                "doi": probe["doi"],
                "n_files": probe["n_files"],
                "total_bytes": probe["total_bytes"],
                "license": probe.get("license"),
                "n_files_ge_200mb": probe["n_files_ge_200mb"],
            }
            if probe
            else None
        ),
        "dataverse_probe_error": probe_error,
        "local_dataverse_files": local_dv,
        "skipped": {
            "mesh_archives": "none present as discrete archives on Dataverse listing; STL via STLGen.py",
            "files_ge_200mb": (probe["files_ge_200mb"] if probe else []),
            "large_tabs_not_mirrored": [
                "Diffusion_Aug_Set_* Input_Vectors.tab / Cw.tab / Volume.tab / etc.",
                "Full GeometricMeasures for CRS2/CRS3 and Diffusion sets",
                "Blender lighting .blend files",
            ],
        },
    }
    if out_manifest is not None:
        out_manifest = Path(out_manifest)
        out_manifest.parent.mkdir(parents=True, exist_ok=True)
        out_manifest.write_text(json.dumps(result, indent=2, sort_keys=True))
    return result
