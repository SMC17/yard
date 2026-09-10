"""L2 panel / BEM teacher (Capytaine) for Yard-Sea-v0.

Sits between Michell L1.5 (thin-ship wave drag) and OpenFOAM L3 (RANS).

Uses public Capytaine (linear potential-flow BEM) on:
1. Optional STL (Ship-D / exploratory mesh) via ``load_mesh``
2. Built-in parallelepiped from ``HullState`` (default thin call)

Reports **Cw/Cd-like** scalars from radiation damping + diffraction surge force.
These are exploratory ranking proxies — **not** steady Michell Cw, **not** ITTC
powering, **not** class / model-test validated.

Fidelity: **L2_panel_bem** when Capytaine solves; **L2_pending** on skip.
"""

from __future__ import annotations

import math
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..hull import G, RHO_SW, HullState
from ..resistance_l1 import ResistanceResult, ittc57_cf

FIDELITY = "L2_panel_bem"
FIDELITY_PENDING = "L2_pending"
TEACHER = "panel_l2"


@dataclass
class PanelAvailability:
    capytaine: bool = False
    version: str | None = None
    error: str | None = None

    @property
    def available(self) -> bool:
        return self.capytaine

    def to_dict(self) -> dict[str, Any]:
        return {
            "capytaine": self.capytaine,
            "version": self.version,
            "error": self.error,
            "available": self.available,
            "install_hint": "pip install 'capytaine>=2.2'  # optional L2 panel/BEM",
            "meshmagick": False,  # not on PyPI for this box; Capytaine+meshio covers STL
            "hydrogym": False,  # HydroGym/FluidGym are RL CFD envs — not a ship panel teacher
        }


def detect() -> PanelAvailability:
    """Probe Capytaine import (side-effect free aside from import)."""
    try:
        import capytaine as cpt  # noqa: F401

        ver = getattr(cpt, "__version__", None)
        return PanelAvailability(capytaine=True, version=str(ver) if ver else None)
    except Exception as exc:  # pragma: no cover - import failure path
        return PanelAvailability(capytaine=False, error=f"{type(exc).__name__}: {exc}")


def detect_panel() -> PanelAvailability:
    """Alias matching OpenFOAM-style detect_* naming."""
    return detect()


def _pending(
    *,
    fn: float,
    u: float,
    reason: str,
    avail: PanelAvailability,
    notes: str,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    base = ResistanceResult(
        Fn=fn,
        Rn=0.0,
        Cf=0.0,
        k1=float("nan"),
        Cw=float("nan"),
        Rt_N=float("nan"),
        Ct=float("nan"),
        fidelity=FIDELITY_PENDING,
        notes=notes,
    ).to_dict()
    base.update(
        {
            "skipped": True,
            "skip_reason": reason,
            "teacher": TEACHER,
            "Cd": None,
            "Cw_like": None,
            "Cd_like": None,
            "U": u,
            "availability": avail.to_dict(),
            "backend": None,
        }
    )
    if extra:
        base.update(extra)
    return base


def encounter_omega(L: float, *, wavelength_frac: float = 1.0) -> float:
    """Deep-water encounter ω for a representative wavelength ∼ wavelength_frac·L."""
    lam = max(float(L) * float(wavelength_frac), 1e-3)
    k = 2.0 * math.pi / lam
    return float(math.sqrt(G * k))


def hull_parallelepiped_mesh(
    h: HullState,
    *,
    resolution: tuple[int, int, int] = (12, 4, 4),
):
    """Immersed parallelepiped sized to L×B×T (Capytaine z≤0 immersed)."""
    import capytaine as cpt

    L, B, T = float(h.L), float(h.B), float(h.T)
    # Deck / free surface at z=0; keel at z=-T
    mesh = cpt.mesh_parallelepiped(
        size=(L, B, T),
        center=(0.0, 0.0, -0.5 * T),
        resolution=resolution,
        name="yard_sea_l2_box",
    )
    return mesh.immersed_part()


def load_stl_immersed(
    stl_path: Path | str,
    *,
    draft: float | None = None,
):
    """Load STL and keep immersed part (z≤0).

    If the mesh sits with keel near z=0 (Ship-D / yard export convention),
    shift by ``-draft`` (or inferred height) so the free surface is at z=0.
    """
    import capytaine as cpt

    path = Path(stl_path)
    mesh = cpt.load_mesh(str(path), file_format="stl")
    verts = np.asarray(mesh.vertices, dtype=np.float64)
    zmin = float(verts[:, 2].min())
    zmax = float(verts[:, 2].max())
    # Heuristic: if mesh is mostly z>=0, treat zmax as design WL (or use draft)
    if zmin >= -1e-6:
        shift = float(draft) if draft is not None else (zmax - zmin)
        mesh = mesh.translated_z(-shift)
    return mesh.immersed_part()


def _ref_area(h: HullState) -> float:
    """Frontal-ish reference for Cd-like: B·T (exploratory, not ITTC S)."""
    return max(float(h.B) * float(h.T), 1e-6)


def _wetted_ref(h: HullState) -> float:
    return max(float(h.wetted_approx()), 1e-6)


def run(
    h: HullState | None = None,
    *,
    Fn: float | None = None,
    stl_path: Path | str | None = None,
    resolution: tuple[int, int, int] = (12, 4, 4),
    omega: float | None = None,
    rho: float = RHO_SW,
    wavelength_frac: float = 1.0,
    availability: PanelAvailability | None = None,
) -> dict[str, Any]:
    """Run Capytaine radiation (Surge) + diffraction → Cw/Cd-like.

    Parameters
    ----------
    h
        Hull principals (default ``HullState()``).
    Fn
        Froude number override.
    stl_path
        Optional STL; otherwise parallelepiped from ``h``.
    resolution
        Capytaine parallelepiped face counts (nx, ny, nz) when not using STL.
    omega
        Wave angular frequency [rad/s]. Default: deep-water ω for λ≈L.
    """
    avail = availability if availability is not None else detect()
    hull = h or HullState()
    fn = float(Fn if Fn is not None else hull.Fn)
    L = float(hull.L)
    U = fn * math.sqrt(G * L)

    if not avail.available:
        return _pending(
            fn=fn,
            u=U,
            reason="capytaine_missing",
            avail=avail,
            notes=(
                "Capytaine not installed — L2 panel/BEM skipped. "
                "pip install 'capytaine>=2.2'. Not ITTC / not class."
            ),
        )

    import capytaine as cpt

    geom_source = "parallelepiped"
    try:
        if stl_path is not None:
            mesh = load_stl_immersed(stl_path, draft=float(hull.T))
            geom_source = f"stl:{Path(stl_path).name}"
            if getattr(mesh, "nb_faces", 0) < 4:
                return _pending(
                    fn=fn,
                    u=U,
                    reason="stl_mesh_empty",
                    avail=avail,
                    notes="STL immersed part has too few faces. Not ITTC / not class.",
                    extra={"geom_source": geom_source},
                )
        else:
            mesh = hull_parallelepiped_mesh(hull, resolution=resolution)

        body = cpt.FloatingBody(
            mesh=mesh,
            dofs=cpt.rigid_body_dofs(rotation_center=(0.0, 0.0, -0.5 * float(hull.T))),
            name="yard_sea_l2",
        )
        om = float(omega) if omega is not None else encounter_omega(L, wavelength_frac=wavelength_frac)
        solver = cpt.BEMSolver()

        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            rad = solver.solve(
                cpt.RadiationProblem(
                    body=body, radiating_dof="Surge", omega=om, rho=float(rho)
                )
            )
            dif = solver.solve(
                cpt.DiffractionProblem(
                    body=body, wave_direction=0.0, omega=om, rho=float(rho)
                )
            )
    except Exception as exc:
        return _pending(
            fn=fn,
            u=U,
            reason="capytaine_failed",
            avail=avail,
            notes=f"Capytaine solve failed ({type(exc).__name__}: {exc}). Not ITTC / not class.",
            extra={"geom_source": geom_source},
        )

    b11 = float(np.real(rad.radiation_dampings["Surge"]))
    a11 = float(np.real(rad.added_masses["Surge"]))
    fx = dif.forces["Surge"]
    fx_abs = float(np.abs(fx))

    S_front = _ref_area(hull)
    S_wet = _wetted_ref(hull)
    q = 0.5 * float(rho) * (U**2)

    # Cd-like: |F_surge| / (q · B·T) — diffraction excitation ranking proxy
    cd_like = fx_abs / (q * S_front) if q > 0 else float("nan")
    # Cw-like: radiation damping / (½ ρ U S_wet) — wave-radiation ranking proxy
    cw_like = b11 / (0.5 * float(rho) * U * S_wet) if U > 0 else float("nan")

    rn = U * L / 1.19e-6
    cf = ittc57_cf(rn)
    # Exploratory total: viscous Cf·S_wet term + damping·U as wave-ish force
    rf = q * cf * S_wet
    rw = b11 * U  # damping force at speed U (linearised proxy)
    rt = rf + rw
    denom = q * (L**2)  # Ship-D / Michell-ish LOA² convention for Ct
    ct = rt / denom if denom > 0 else float("nan")
    cw = rw / denom if denom > 0 else float("nan")

    notes = (
        "Capytaine linear BEM (radiation Surge + diffraction head seas) on "
        f"{geom_source}. Cw/Cd-like are exploratory panel ranking proxies — "
        "not steady Michell Cw, not ITTC powering, not class / model-test."
    )

    base = ResistanceResult(
        Fn=fn,
        Rn=rn,
        Cf=cf,
        k1=float("nan"),
        Cw=cw,
        Rt_N=rt,
        Ct=ct,
        fidelity=FIDELITY,
        notes=notes,
    ).to_dict()
    base.update(
        {
            "skipped": False,
            "skip_reason": None,
            "teacher": TEACHER,
            "Cd": cd_like,
            "Cd_like": cd_like,
            "Cw_like": cw_like,
            "Rw_N": rw,
            "Rf_N": rf,
            "U": U,
            "omega": om,
            "wavelength_frac": float(wavelength_frac),
            "added_mass_surge": a11,
            "radiation_damping_surge": b11,
            "F_surge_abs": fx_abs,
            "S_front_m2": S_front,
            "S_wet_m2": S_wet,
            "L_m": L,
            "nb_faces": int(getattr(mesh, "nb_faces", 0)),
            "geom_source": geom_source,
            "backend": "capytaine",
            "capytaine_version": avail.version,
            "availability": avail.to_dict(),
            "resolution": list(resolution),
        }
    )
    return base


def run_panel(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Alias for gallery / CLI."""
    return run(*args, **kwargs)


def run_teacher(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Shared teacher protocol alias."""
    return run(*args, **kwargs)
