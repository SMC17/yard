"""Exploratory mesh export for Yard-Sea-v0 hulls.

Default path writes a watertight *box* STL from L×B×T (honestly labeled).
Optional CadQuery path (if installed) builds a soft-filleted prism — still not
Ship-D surface fidelity.
"""

from __future__ import annotations

from pathlib import Path

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

    def normal(a, b, c):
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx = uy * vz - uz * vy
        ny = uz * vx - ux * vz
        nz = ux * vy - uy * vx
        n = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
        return nx / n, ny / n, nz / n

    lines = [f"solid yard_sea_v0_box L={L} B={B} T={T} Cb={h.Cb}"]
    for a, b, c in faces:
        nx, ny, nz = normal(a, b, c)
        lines.append(f"  facet normal {nx:.6e} {ny:.6e} {nz:.6e}")
        lines.append("    outer loop")
        for p in (a, b, c):
            lines.append(f"      vertex {p[0]:.6e} {p[1]:.6e} {p[2]:.6e}")
        lines.append("    endloop")
        lines.append("  endfacet")
    lines.append("endsolid yard_sea_v0_box")
    path.write_text("\n".join(lines) + "\n")
    return path


def try_cadquery_chine(h: HullState, path: Path) -> Path | None:
    """If cadquery is installed, export a soft-filleted prism; else None."""
    try:
        import cadquery as cq  # type: ignore
    except ImportError:
        return None
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    solid = (
        cq.Workplane("XY")
        .box(h.L, h.B, h.T)
        .edges("|Z")
        .fillet(min(h.B, h.T) * 0.05)
    )
    cq.exporters.export(solid, str(path))
    return path
