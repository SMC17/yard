"""Real hull lines for the tank-validation hulls (KCS, KVLCC2, DTMB 5415).

Geometry comes from the public CFD-workshop files fetched by
``data/fetch/fetch_yard_data.py`` into ``data/cache/`` (licence not stated by
the hosts, so they are fetched, never committed):

* KCS      — Tokyo 2015 ``KCS_hull_SVA.igs`` (55 untrimmed NURBS patches, full
             scale, x fwd from AP, z up from baseline).
* KVLCC2   — Gothenburg 2000 ``kvlcc2.fix`` body-plan offsets (full scale).
* DTMB5415 — Gothenburg 2000 ``5415_static.net`` structured surface grid
             (model scale 5.72 m, x aft from FP; mapped to x fwd from AP).

Every source is turned into structured surface grids (n, m, 3), sliced into a
half-breadth table y(x, z) and integrated. The derived hydrostatics are checked
against the published particulars (``data/reference``) in the tests, which is
how we know the geometry processing is right.

Holtrop & Mennen (1982, 1984) bulb / transom inputs are read off the lines:

* ``A_BT`` — transverse bulb area at the FP: section area at x = FP below the
             waterline (both sides), as defined by Holtrop & Mennen.
* ``h_B``  — height of the centroid of A_BT above the keel. A_BT below 0.5 % of
             the midship-section area (a stem sliver, e.g. DTMB 5415 whose sonar
             dome sits aft of the FP) is reported as 0 = no bulb.
* ``A_T``  — immersed transom area at rest. Convention: section area below the
             waterline 0.002 L forward of the aft end of the submerged hull (the
             slice exactly at the end is degenerate). Set to 0 for KVLCC2, whose
             offsets end at a cruiser-stern contour, not a transom.
"""

from __future__ import annotations

import dataclasses
import io
import math
import zipfile
from functools import lru_cache
from pathlib import Path
from typing import Any

import numpy as np

HULLS = ("KCS", "KVLCC2", "DTMB5415")

_FILES = {
    "KCS": "t2015_kcs_hull_sva.zip",
    "KVLCC2": "g2000_kvlcc2_offsets.zip",
    "DTMB5415": "g2000_dtmb5415_static.net",
}


def cache_dir() -> Path:
    from .validation import repo_root

    return repo_root() / "data" / "cache"


def available(hull: str) -> bool:
    return (cache_dir() / _FILES[hull]).is_file()


# ------------------------------------------------------------------ readers
def _iges_entities(text: str) -> list[dict[str, Any]]:
    D: list[str] = []
    P: dict[int, str] = {}
    for line in text.splitlines():
        t = line[72:73]
        if t == "D":
            D.append(line)
        elif t == "P":
            P[int(line[73:80])] = line[:64]
    out = []
    for i in range(0, len(D) - 1, 2):
        a, b = D[i], D[i + 1]
        typ, p0, pc = int(a[0:8]), int(a[8:16]), int(b[24:32])
        txt = "".join(P[s] for s in range(p0, p0 + pc)).split(";")[0]
        out.append({"type": typ, "xform": int(a[48:56] or 0), "params": [f.strip() for f in txt.split(",")]})
    return out


def _f(s: str) -> float:
    return float(s.replace("D", "E").replace("d", "e"))


def _nurbs128_grid(params: list[str], nu: int, nv: int) -> np.ndarray:
    """Evaluate an IGES type-128 rational B-spline surface on a uniform (u, v) grid."""
    from scipy.interpolate import BSpline

    v = params[1:]
    K1, K2, M1, M2 = (int(x) for x in v[:4])
    i = 9
    nS, nT, nW = K1 + M1 + 2, K2 + M2 + 2, (K1 + 1) * (K2 + 1)
    S = np.array([_f(x) for x in v[i:i + nS]]); i += nS
    T = np.array([_f(x) for x in v[i:i + nT]]); i += nT
    W = np.array([_f(x) for x in v[i:i + nW]]).reshape(K2 + 1, K1 + 1).T; i += nW
    C = np.array([_f(x) for x in v[i:i + 3 * nW]]).reshape(K2 + 1, K1 + 1, 3).transpose(1, 0, 2); i += 3 * nW
    U0, U1, V0, V1 = (_f(x) for x in v[i:i + 4])
    u = np.clip(np.linspace(U0, U1, nu), S[M1], S[-M1 - 1])
    w = np.clip(np.linspace(V0, V1, nv), T[M2], T[-M2 - 1])
    Bu = BSpline.design_matrix(u, S, M1).toarray()
    Bv = BSpline.design_matrix(w, T, M2).toarray()
    den = Bu @ W @ Bv.T
    num = np.einsum("ia,abk,jb->ijk", Bu, W[..., None] * C, Bv)
    return num / den[..., None]


def _read_kcs(path: Path, n: int = 40) -> list[np.ndarray]:
    with zipfile.ZipFile(path) as z:
        name = next(x for x in z.namelist() if x.lower().endswith(".igs"))
        text = z.read(name).decode("latin-1")
    grids = []
    for e in _iges_entities(text):
        if e["type"] != 128:
            continue
        if e["xform"]:
            raise ValueError("transformed IGES entity not supported")
        g = _nurbs128_grid(e["params"], n, n)
        g[..., 1] = np.abs(g[..., 1])
        grids.append(g)
    return grids


def _read_kvlcc2(path: Path) -> list[np.ndarray]:
    with zipfile.ZipFile(path) as z:
        name = next(x for x in z.namelist() if x.lower().endswith(".fix"))
        lines = z.read(name).decode("latin-1").splitlines()
    t = " ".join(lines[1:]).split()
    nst, i = int(t[0]), 1
    secs = []
    for _ in range(nst):
        x, m = float(t[i]), int(t[i + 1]); i += 2
        b = np.array(t[i:i + m], float); i += m
        h = np.array(t[i:i + m], float); i += m
        secs.append((x, b, h))
    # Resample each station to a common normalised girth so stations form a grid.
    s_new = np.linspace(0.0, 1.0, 120)
    rows = []
    for x, b, h in secs:
        d = np.r_[0.0, np.cumsum(np.hypot(np.diff(b), np.diff(h)))]
        s = d / d[-1] if d[-1] > 0 else np.linspace(0, 1, d.size)
        s, idx = np.unique(s, return_index=True)
        rows.append(np.stack([np.full_like(s_new, x), np.interp(s_new, s, b[idx]), np.interp(s_new, s, h[idx])], -1))
    return [np.stack(rows)]


def _read_5415(path: Path) -> list[np.ndarray]:
    t = path.read_text().split()
    ni, nj, nk = int(t[1]), int(t[2]), int(t[3])
    n = ni * nj * nk
    a = np.array(t[4:4 + 3 * n], float)
    x, y, z = (a[k * n:(k + 1) * n].reshape(nj, ni) for k in range(3))
    # Source: x aft from FP, Lpp 5.72 m; map to x fwd from AP.
    return [np.stack([5.72 - x, np.abs(y), z], -1)]


_READERS = {"KCS": _read_kcs, "KVLCC2": _read_kvlcc2, "DTMB5415": _read_5415}

# Particulars of the geometry files (frame / scale of the file itself).
_FRAME = {
    "KCS": {"Lpp": 230.0, "T": 10.8, "z_keel": 0.0, "transom": True,
            "source": "Tokyo 2015 KCS_hull_SVA.igs (full scale)"},
    "KVLCC2": {"Lpp": 320.0, "T": 20.8, "z_keel": 0.0, "transom": False,
               "source": "Gothenburg 2000 kvlcc2.fix offsets (full scale)"},
    "DTMB5415": {"Lpp": 5.72, "T": 0.248, "z_keel": None, "transom": True,
                 "source": "Gothenburg 2000 5415_static.net (model 5.72 m)"},
}


@lru_cache(maxsize=8)
def surface(hull: str) -> tuple[np.ndarray, ...]:
    path = cache_dir() / _FILES[hull]
    if not path.is_file():
        raise FileNotFoundError(f"{path} missing: run python data/fetch/fetch_yard_data.py")
    return tuple(_READERS[hull](path))


# ------------------------------------------------------------------ slicing
def _triangles(grids: tuple[np.ndarray, ...]) -> np.ndarray:
    tris = []
    for g in grids:
        a, b, c, d = g[:-1, :-1], g[1:, :-1], g[1:, 1:], g[:-1, 1:]
        tris.append(np.stack([a, b, c], -2).reshape(-1, 3, 3))
        tris.append(np.stack([a, c, d], -2).reshape(-1, 3, 3))
    return np.concatenate(tris)


def halfbreadth(hull: str, xs: np.ndarray, zs: np.ndarray) -> np.ndarray:
    """Half-breadth table Y[i, j] = max |y| of the hull surface at (xs[i], zs[j]) (0 outside)."""
    tri = _triangles(surface(hull))
    xs, zs = np.asarray(xs, float), np.asarray(zs, float)
    Y = np.zeros((xs.size, zs.size))
    tx = tri[..., 0]
    lo, hi = tx.min(1), tx.max(1)
    for i, x in enumerate(xs):
        sel = tri[(lo <= x) & (hi >= x) & (hi > lo)]
        if sel.size == 0:
            continue
        pts = []
        for e0, e1 in ((0, 1), (1, 2), (2, 0)):
            p, q = sel[:, e0], sel[:, e1]
            dx = q[:, 0] - p[:, 0]
            with np.errstate(divide="ignore", invalid="ignore"):
                t = (x - p[:, 0]) / dx
            ok = (dx != 0) & (t >= 0) & (t <= 1)
            with np.errstate(invalid="ignore"):
                pts.append(np.where(ok[:, None], p[:, 1:] + t[:, None] * (q[:, 1:] - p[:, 1:]), np.nan))
        P = np.stack(pts, 1)  # (ntri, 3 edges, (y, z))
        segs = []
        for a, b in ((0, 1), (1, 2), (0, 2)):
            m = ~np.isnan(P[:, a, 0]) & ~np.isnan(P[:, b, 0])
            segs.append(np.concatenate([P[m, a], P[m, b]], 1))
        S = np.concatenate(segs)  # (nseg, y1 z1 y2 z2)
        if S.size == 0:
            continue
        y1, z1, y2, z2 = S.T
        zl, zh = np.minimum(z1, z2), np.maximum(z1, z2)
        for j, z in enumerate(zs):
            m = (zl <= z) & (zh >= z)
            if not m.any():
                continue
            dz = z2[m] - z1[m]
            with np.errstate(divide="ignore", invalid="ignore"):
                y = np.where(np.abs(dz) > 1e-12, y1[m] + (z - z1[m]) / dz * (y2[m] - y1[m]), np.maximum(y1[m], y2[m]))
            Y[i, j] = float(np.nanmax(y))
    return Y


# ------------------------------------------------------------------ particulars
@dataclasses.dataclass(frozen=True)
class LinesParticulars:
    hull: str
    Lpp: float
    T: float
    z_keel: float
    B: float
    vol: float
    S: float
    Cb: float
    Cm: float
    Cp: float
    Cwp: float
    lcb_pct: float
    Lwl: float
    A_BT: float
    h_B: float
    A_T: float
    x_aft: float
    x_fwd: float
    source: str

    def scaled(self, lam: float) -> "LinesParticulars":
        """Geometric scaling by length ratio lam (model = full / lam)."""
        k = 1.0 / lam
        return dataclasses.replace(self, Lpp=self.Lpp * k, T=self.T * k, z_keel=self.z_keel * k, B=self.B * k,
                                   vol=self.vol * k ** 3, S=self.S * k ** 2, Lwl=self.Lwl * k,
                                   A_BT=self.A_BT * k ** 2, h_B=self.h_B * k, A_T=self.A_T * k ** 2,
                                   x_aft=self.x_aft * k, x_fwd=self.x_fwd * k)

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


def _wetted_area(grids: tuple[np.ndarray, ...], z_wl: float) -> float:
    """Area of the surface below z_wl (both sides), triangles clipped by linear fraction."""
    tri = _triangles(grids)
    a = 0.5 * np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
    z = tri[..., 2]
    zmin, zmax = z.min(1), z.max(1)
    frac = np.clip((z_wl - zmin) / np.where(zmax > zmin, zmax - zmin, 1.0), 0.0, 1.0)
    frac = np.where(zmax <= zmin, (zmin <= z_wl).astype(float), frac)
    return float(2.0 * np.sum(a * frac))


def _keel(hull: str) -> float:
    zk = _FRAME[hull]["z_keel"]
    if zk is not None:
        return float(zk)
    # Keel at midship: lowest surface point near Lpp/2.
    g = np.concatenate([s.reshape(-1, 3) for s in surface(hull)])
    L = _FRAME[hull]["Lpp"]
    near = np.abs(g[:, 0] - 0.5 * L) < 0.02 * L
    return float(g[near, 2].min())


@lru_cache(maxsize=8)
def particulars(hull: str, nx: int = 241, nz: int = 81) -> LinesParticulars:
    fr = _FRAME[hull]
    L, T = float(fr["Lpp"]), float(fr["T"])
    zk = _keel(hull)
    zwl = zk + T
    g = np.concatenate([s.reshape(-1, 3) for s in surface(hull)])
    sub = g[g[:, 2] <= zwl + 1e-9]
    x_aft, x_fwd = float(sub[:, 0].min()), float(sub[:, 0].max())
    xs = np.linspace(x_aft, x_fwd, nx)
    zs = np.linspace(float(sub[:, 2].min()), zwl, nz)
    Y = halfbreadth(hull, xs, zs)
    A = 2.0 * np.trapezoid(Y, zs, axis=1)
    vol = float(np.trapezoid(A, xs))
    y_wl = Y[:, -1]
    B = 2.0 * float(y_wl.max())
    wet = y_wl > 1e-6 * L
    Lwl = float(xs[wet].max() - xs[wet].min()) if wet.any() else L
    Awp = 2.0 * float(np.trapezoid(y_wl, xs))
    Am = float(np.interp(0.5 * L, xs, A))
    lcb = float(np.trapezoid(A * xs, xs) / vol)
    # Bulb: section at FP.
    yf = halfbreadth(hull, np.array([L]), zs)[0]
    A_BT = 2.0 * float(np.trapezoid(yf, zs))
    h_B = float(2.0 * np.trapezoid(yf * zs, zs) / A_BT - zk) if A_BT > 0 else 0.0
    if A_BT < 0.005 * B * T * Am / (B * T):  # < 0.5 % of midship area: stem sliver, no bulb
        A_BT, h_B = 0.0, 0.0
    # Transom: section just inside the aft end of the submerged hull.
    A_T = 0.0
    if fr["transom"]:
        yt = halfbreadth(hull, np.array([x_aft + 0.002 * L]), zs)[0]
        A_T = 2.0 * float(np.trapezoid(yt, zs))
    return LinesParticulars(
        hull=hull, Lpp=L, T=T, z_keel=zk, B=B, vol=vol, S=_wetted_area(surface(hull), zwl),
        Cb=vol / (L * B * T), Cm=Am / (B * T), Cp=vol / (Am * L), Cwp=Awp / (L * B),
        lcb_pct=(lcb - 0.5 * L) / L * 100.0, Lwl=Lwl, A_BT=A_BT, h_B=h_B, A_T=A_T,
        x_aft=x_aft, x_fwd=x_fwd, source=str(fr["source"]),
    )


def michell_offsets(hull: str, *, scale_to_L: float | None = None, nx: int = 81, nz: int = 21
                    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(Y, X, Z) for ModMichell: X from aft end of the submerged hull to the bulb tip,
    Z from 0 (waterline) to -draft (deepest point). Optionally scaled so Lpp = scale_to_L."""
    p = particulars(hull)
    if nx % 2 == 0:
        nx += 1
    zwl = p.z_keel + p.T
    g = np.concatenate([s.reshape(-1, 3) for s in surface(hull)])
    zbot = float(g[g[:, 2] <= zwl][:, 2].min())
    xs = np.linspace(p.x_aft, p.x_fwd, nx)
    zs = np.linspace(zwl, zbot, nz)
    Y = halfbreadth(hull, xs, zs)
    k = 1.0 if scale_to_L is None else float(scale_to_L) / p.Lpp
    return Y * k, (xs - p.x_aft) * k, (zs - zwl) * k
