"""Exploratory mesh export for Yard-Sea-v0 hulls.

Paths (best → honest fallback):
1. CadQuery/OCCT soft-chine loft (tapered bow/stern from L,B,T,Cb + optional Lb/Ls)
2. Pure-Python tapered prism STL (same planform, faceted — clearly better than a box)
3. Axis-aligned box STL (legacy / explicit)

Not Ship-D surface fidelity / not class-approved.
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

from .hull import HullState


def write_box_stl(h: HullState, path: Path) -> Path:
    """Axis-aligned box hull: LOA×B×T, origin at midship/keel/centerline."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    L, B, T = h.L, h.B, h.T
    x0, x1 = -L / 2, L / 2
    y0, y1 = -B / 2, B / 2
    z0, z1 = 0.0, T
    faces = [
        ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0)),
        ((x0, y0, z0), (x1, y1, z0), (x0, y1, z0)),
        ((x0, y0, z1), (x1, y1, z1), (x1, y0, z1)),
        ((x0, y0, z1), (x0, y1, z1), (x1, y1, z1)),
        ((x0, y0, z0), (x1, y0, z1), (x1, y0, z0)),
        ((x0, y0, z0), (x0, y0, z1), (x1, y0, z1)),
        ((x0, y1, z0), (x1, y1, z0), (x1, y1, z1)),
        ((x0, y1, z0), (x1, y1, z1), (x0, y1, z1)),
        ((x0, y0, z0), (x0, y1, z0), (x0, y1, z1)),
        ((x0, y0, z0), (x0, y1, z1), (x0, y0, z1)),
        ((x1, y0, z0), (x1, y0, z1), (x1, y1, z1)),
        ((x1, y0, z0), (x1, y1, z1), (x1, y1, z0)),
    ]
    return _write_ascii_stl(path, "yard_sea_v0_box", faces, meta=f"L={L} B={B} T={T} Cb={h.Cb}")


def taper_fractions(
    h: HullState,
    lb_frac: float | None = None,
    ls_frac: float | None = None,
) -> tuple[float, float, float]:
    """Return (Lb/L, Ls/L, midbody/L) for planform taper.

    Higher Cb → longer parallel midbody. Optional Ship-D Lb/Ls fractions override.
    """
    if lb_frac is not None and ls_frac is not None:
        lb = max(0.05, min(0.45, float(lb_frac)))
        ls = max(0.05, min(0.45, float(ls_frac)))
        mid = max(0.05, 1.0 - lb - ls)
        return lb, ls, mid
    # midbody grows with Cb (exploratory mapping, not HP)
    mid = 0.18 + 0.55 * min(1.0, max(0.0, (h.Cb - 0.45) / 0.50))
    rem = max(0.15, 1.0 - mid)
    # lcb > 0 (forward) → slightly more stern taper
    bow_share = 0.5 - 2.5 * h.lcb_frac
    bow_share = max(0.35, min(0.65, bow_share))
    lb = rem * bow_share
    ls = rem * (1.0 - bow_share)
    return lb, ls, mid


def station_beam(
    s: float,
    B: float,
    lb: float,
    ls: float,
    *,
    bow_tip: float = 0.08,
    stern_tip: float = 0.38,
) -> float:
    """Full beam at station fraction s∈[0,1] from bow→stern (smooth cosine tapers)."""
    import math

    s = max(0.0, min(1.0, s))
    mid_start = lb
    mid_end = 1.0 - ls
    if s <= mid_start:
        t = 0.0 if mid_start <= 1e-9 else s / mid_start
        w = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t))
        return B * (bow_tip + (1.0 - bow_tip) * w)
    if s >= mid_end:
        t = 0.0 if ls <= 1e-9 else (s - mid_end) / ls
        w = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t))
        return B * (1.0 + (stern_tip - 1.0) * w)
    return B


def _normal(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx = uy * vz - uz * vy
    ny = uz * vx - ux * vz
    nz = ux * vy - uy * vx
    n = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
    return nx / n, ny / n, nz / n


def _write_ascii_stl(
    path: Path,
    solid_name: str,
    faces: Sequence[tuple],
    *,
    meta: str = "",
) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    header = f"solid {solid_name}" + (f" {meta}" if meta else "")
    lines = [header]
    for a, b, c in faces:
        nx, ny, nz = _normal(a, b, c)
        lines.append(f"  facet normal {nx:.6e} {ny:.6e} {nz:.6e}")
        lines.append("    outer loop")
        for p in (a, b, c):
            lines.append(f"      vertex {p[0]:.6e} {p[1]:.6e} {p[2]:.6e}")
        lines.append("    endloop")
        lines.append("  endfacet")
    lines.append(f"endsolid {solid_name}")
    path.write_text("\n".join(lines) + "\n")
    return path


def write_tapered_prism_stl(
    h: HullState,
    path: Path,
    *,
    lb_frac: float | None = None,
    ls_frac: float | None = None,
    n_stations: int = 17,
) -> Path:
    """Facets a tapered bow/stern prism (soft-chine-ish stations) without CadQuery.

    Clearly richer than write_box_stl: variable beam along length from Cb/LCB
    (or explicit Ship-D Lb/Ls fractions).
    """
    path = Path(path)
    L, B, T = h.L, h.B, h.T
    lb, ls, _mid = taper_fractions(h, lb_frac, ls_frac)
    n = max(5, int(n_stations))
    # station rings: soft-chine hex (keel, chine×2, deck×2 mirrored)
    chine_z = 0.35 * T
    keel_frac = 0.12
    rings: list[list[tuple[float, float, float]]] = []
    for i in range(n):
        s = i / (n - 1)
        x = -L / 2 + s * L
        beam = max(station_beam(s, B, lb, ls), 0.05 * B)
        hb = beam / 2
        hk = max(hb * keel_frac, 0.01)
        rings.append(
            [
                (x, hk, 0.0),
                (x, hb * 0.95, chine_z),
                (x, hb, T),
                (x, -hb, T),
                (x, -hb * 0.95, chine_z),
                (x, -hk, 0.0),
            ]
        )

    faces: list[tuple] = []
    m = len(rings[0])
    for i in range(n - 1):
        r0, r1 = rings[i], rings[i + 1]
        for j in range(m):
            j2 = (j + 1) % m
            a, b = r0[j], r0[j2]
            c, d = r1[j2], r1[j]
            faces.append((a, b, c))
            faces.append((a, c, d))
    # bow / stern caps (fan from centroid of ring)
    for ring, reverse in ((rings[0], True), (rings[-1], False)):
        cx = sum(p[0] for p in ring) / m
        cy = sum(p[1] for p in ring) / m
        cz = sum(p[2] for p in ring) / m
        center = (cx, cy, cz)
        for j in range(m):
            j2 = (j + 1) % m
            if reverse:
                faces.append((center, ring[j2], ring[j]))
            else:
                faces.append((center, ring[j], ring[j2]))

    meta = f"L={L} B={B} T={T} Cb={h.Cb} Lb={lb:.3f} Ls={ls:.3f} n={n}"
    return _write_ascii_stl(path, "yard_sea_v0_tapered_prism", faces, meta=meta)


def try_cadquery_chine(
    h: HullState,
    path: Path,
    *,
    lb_frac: float | None = None,
    ls_frac: float | None = None,
    n_stations: int = 9,
) -> Path | None:
    """CadQuery soft-chine loft; returns path or None if CadQuery/OCCT unavailable."""
    try:
        import cadquery as cq  # type: ignore
    except ImportError:
        return None

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    L, B, T = h.L, h.B, h.T
    lb, ls, _mid = taper_fractions(h, lb_frac, ls_frac)
    n = max(5, int(n_stations))
    chine_z = 0.35 * T
    keel_frac = 0.12

    def add_section(wp, beam: float, draft: float):
        hb = max(beam, 0.05 * B) / 2
        hk = max(hb * keel_frac, 0.01)
        pts = [
            (hk, 0.0),
            (hb * 0.95, chine_z),
            (hb, draft),
            (-hb, draft),
            (-hb * 0.95, chine_z),
            (-hk, 0.0),
        ]
        return wp.polyline(pts).close()

    wp = cq.Workplane("YZ")
    prev_x = None
    for i in range(n):
        s = i / (n - 1)
        x = -L / 2 + s * L
        beam = station_beam(s, B, lb, ls)
        if prev_x is None:
            wp = wp.workplane(offset=x)
        else:
            wp = wp.workplane(offset=x - prev_x)
        wp = add_section(wp, beam, T)
        prev_x = x

    solid = wp.loft(ruled=False)
    # Best-effort soft edges (may no-op depending on OCCT edge classification)
    try:
        r = min(B, T) * 0.03
        if r > 1e-3:
            solid = solid.edges("|X").fillet(r)
    except Exception:
        pass

    cq.exporters.export(solid, str(path))
    return path


def try_shipd_principals_loft(
    h: HullState,
    path: Path,
    *,
    lb_frac: float,
    ls_frac: float,
) -> Path | None:
    """Loft using explicit Ship-D Lb/Ls fractions via CadQuery (approx surface).

    For the real Ship-D Hull_Parameterization mesh, use ``write_shipd_stl`` /
    ``shipd_surface.generate_stl`` with a length-45 vector.
    """
    return try_cadquery_chine(h, path, lb_frac=lb_frac, ls_frac=ls_frac)


def export_hull_stl(
    h: HullState,
    path: Path,
    *,
    prefer: str = "cadquery",
    lb_frac: float | None = None,
    ls_frac: float | None = None,
) -> tuple[Path, str]:
    """Export best available mesh. Returns (path, backend_tag).

    prefer: 'cadquery' | 'tapered' | 'box' (Ship-D HP surface: write_shipd_stl)
    """
    path = Path(path)
    prefer = (prefer or "cadquery").lower()
    if prefer == "box":
        return write_box_stl(h, path), "box"
    if prefer in ("cadquery", "cq", "occt", "auto"):
        out = try_cadquery_chine(h, path, lb_frac=lb_frac, ls_frac=ls_frac)
        if out is not None:
            return out, "cadquery_chine"
    if prefer != "box":
        return (
            write_tapered_prism_stl(h, path, lb_frac=lb_frac, ls_frac=ls_frac),
            "tapered_prism",
        )
    return write_box_stl(h, path), "box"


def cadquery_available() -> bool:
    try:
        import cadquery  # noqa: F401

        return True
    except ImportError:
        return False


def write_shipd_stl(vector, path: Path, **kwargs) -> Path:
    """Export real Ship-D surface STL via vendored Hull_Parameterization.

    Falls back is not provided — callers that want box STL should use write_box_stl.
    ``vector`` is a length-45 Ship-D input (sequence or ShipDVector).
    """
    from .shipd_surface import generate_stl

    return generate_stl(vector, path, **kwargs)

