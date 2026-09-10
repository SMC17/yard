# OpenFOAM runtime install — Yard-Sea-v0 L3 teacher smoke

**Date:** 2026-09-10 ~5:16 PM ET (America/New_York)  
**Outcome:** **SUCCESS** — real OpenFOAM runtime on box; `checkMesh` Mesh OK + `potentialFoam` solved on prepared hull case.

## Probe (before / after)

| Capability | Before | After |
|---|---|---|
| docker / dockerd | absent | **docker.io 26.1.5** installed; dockerd started manually (`policy-rc.d` blocks systemd start) |
| podman | absent | absent |
| snap | absent | absent |
| singularity / apptainer | absent | absent |
| apt `openfoam` | candidate 1912.200626-3+b1 | **installed** (`/usr/bin/{blockMesh,checkMesh,potentialFoam}`) |
| `WM_PROJECT_DIR` | unset | `/usr/share/openfoam` (Debian layout; `FOAM_ETC` required) |
| OpenFOAM Docker image | — | **`opencfd/openfoam-default:2412`** pulled (~1.51 GB) |

Disk: 126G filesystem, ~103G free after installs (~18G used).

## Install path taken

1. **docker.io** via `sudo apt-get install -y docker.io` — worked; daemon not auto-started → started with `sudo dockerd`.
2. **Image pull** `opencfd/openfoam-default:2412` — worked; smoke needs `-case /case` after `source /openfoam/profile.rc` (cwd otherwise becomes `/root`).
3. **apt `openfoam`** (Debian 1912) — worked in parallel; preferred for teacher because native `/usr/bin/*` need only `FOAM_ETC=/usr/share/openfoam/etc` (full `source …/bashrc` is broken: missing `foamEtcFile` / `bin/`).
4. ESI/tarball — not needed.

### Notes for Sean

- Passwordless sudo **works** on this box (`sudo -n`).
- Docker socket: `box` is in group `docker`, but new shells need `sg docker` / re-login; `sudo -n docker` also works.
- If dockerd dies across reboots / agent resets, restart with:
  ```sh
  sudo dockerd --host=unix:///var/run/docker.sock >/tmp/dockerd.log 2>&1 &
  ```
- Debian OpenFOAM env (minimal, no broken bashrc):
  ```sh
  export WM_PROJECT_DIR=/usr/share/openfoam
  export FOAM_ETC=/usr/share/openfoam/etc
  export FOAM_CONFIG_ETC=/usr/share/openfoam/etc
  ```

## Smoke run

- **STL:** `out/sample_box.stl`
- **Case:** `out/foam_runtime_smoke/teacher_case` (via `prepare_case` / `run_teacher`)
- **Native (Debian 1912):**
  - `blockMesh` → 28800 hex cells
  - `checkMesh` → **Mesh OK.**
  - `potentialFoam -writephi` → Continuity error ≈ 1.75e-7, **End**
- **Docker (2412):** same Mesh OK + potentialFoam on `out/foam_runtime_smoke/docker_case`
- **forceCoeffs:** **not produced** (box mesh only; no `hull` patch / no `simpleFoam`). Teacher correctly returns `fidelity=L3_pending`, `skip_reason=forceCoeffs_missing_after_run`.

## Teacher code updates

`yard_sea_v0/teachers/openfoam_l3.py`:

- `detect_openfoam()` finds Debian `/usr/share/openfoam`, reports `debian-openfoam 1912…`, `docker=True`
- `_foam_environ()` sets `FOAM_ETC` / `WM_PROJECT_DIR` for `/usr/bin` solvers
- `run_teacher` runs `blockMesh` → `checkMesh` → `potentialFoam` natively (Allrun skipped: Debian package lacks `WM_PROJECT_DIR/bin/tools`)
- Docker fallback uses `-case /case` + `sg docker` / `sudo -n docker` when bare docker socket access fails

## Tests

`tests/test_openfoam_l3.py`: **7 passed**

## Honest limits

- Mesh + potentialFoam smoke only — **not** resistance / forceCoeffs / ITTC powering
- snappyHexMesh around hull STL not exercised in this smoke (coarse box domain)
- Docker storage driver is **vfs** (overlay mount failed in this environment)
- Not class / not certification

## How to re-run

```sh
cd /workspace/yard-sea-v0
export WM_PROJECT_DIR=/usr/share/openfoam FOAM_ETC=/usr/share/openfoam/etc
.venv/bin/python -c "
from yard_sea_v0.teachers.openfoam_l3 import detect_openfoam, run_teacher
print(detect_openfoam().to_dict())
print(run_teacher('out/sample_box.stl', 0.2, 'out/foam_runtime_smoke/rerun', L=10)['skip_reason'])
"
```
