# Native Debian OpenFOAM forceCoeffs — Yard-Sea-v0

**Date:** 2026-09-10 ~5:50 PM ET (America/New_York)  
**Outcome:** **FIXED (durable workaround)** — native `simpleFoam` + `forceCoeffs` works via `LD_PRELOAD` SHA1 check-bypass; teacher prefers native when healthy and auto-falls back to Docker OF-2412 when not.

## Goal

Make native Debian OpenFOAM `forceCoeffs` work without Docker, **or** document a durable workaround and improve teacher fallback.

## Root cause (corrected)

| Claim | Finding |
|---|---|
| OpenSSL-3 `sha1` / `SECLEVEL` / `CipherString` | **Not the cause.** `OPENSSL_CONF` with `DEFAULT@SECLEVEL=0` + legacy provider **still FATAL**. |
| Actual bug | Debian **OpenFOAM 1912** `Foam::osha1stream::sha1buf` implements `xsputn` but **not** `overflow`. Modern libstdc++ (gcc-12+) may call `overflow` → EOF → `IOstream` bad → `FATAL IO ERROR` on stream **`"sha1"`** when loading `libforces` / any FO. |
| Upstream fix class | OpenFOAM-9 commit `b0c15be` (OSHA1stream C++11 / `overflow`) |

Reproduced baseline (no preload):

```
--> FOAM FATAL IO ERROR:
error in IOstream "sha1" for operation Foam::Ostream& Foam::operator<<(Ostream&, const word&)
```

Empty `functions {}` → `simpleFoam` **End** OK. Both `forceCoeffs` and `forces` FOs, and `postProcess -func forceCoeffs1`, hit the same FATAL.

## Workarounds tried

| Approach | Result |
|---|---|
| `OPENSSL_CONF` + `CipherString = DEFAULT@SECLEVEL=0` | FAIL (still sha1 FATAL) |
| Legacy OpenSSL provider + SECLEVEL=0 | FAIL |
| `forces` FO instead of `forceCoeffs` | FAIL (same OSHA1stream path) |
| `postProcess -func forceCoeffs1` | FAIL |
| Name-targeted C++ `IOstream::check` interpose via `fileName` ABI | FAIL (ABI mismatch) |
| **`LD_PRELOAD` interpose of `IOstream::check` / `fatalCheck`** | **SUCCESS** — Cd matches Docker 2412 |
| Docker `opencfd/openfoam-default:2412` | SUCCESS (prior hybrid path) |

## Durable fix shipped

### `tools/foam_sha1_fix/`

- `foam_sha1_check_bypass.c` — interposes `Foam::IOstream::{check,fatalCheck}` so OSHA1stream badbit does not abort.
- `libfoam_sha1_check_bypass.so` — built artifact (`gcc -shared -fPIC -O2 …`).
- `README.md` — rebuild + manual use notes.
- Teacher auto-builds `.so` via `gcc` if missing (`_ensure_sha1_preload_built`).

Scoped: teacher sets `LD_PRELOAD` **only** for native solver runs that need forceCoeffs (not for mesh-only steps). Digests are for dynamicCode identity; prebuilt `libforces.so` still writes correct coeffs.

### Teacher (`yard_sea_v0/teachers/openfoam_l3.py`)

- **`native_forces_health()`** — static `nm` check: `sha1buf` has `xsputn` but no `overflow` ⇒ bug; OK if plain or preload present.
- **`detect_openfoam()`** exposes `native_forces_ok` / `native_forces_method` / `native_forces_detail`.
- **Prefer native** `simpleFoam` when healthy (`plain` or `sha1_preload`).
- **Auto Docker** when native forces unhealthy (or native solve fails); full Docker pipeline if no native bins.
- Clearer skip hints: OSHA1stream vs OpenSSL SECLEVEL; point at preload + Docker image.

## Smoke evidence

### Native + preload (preferred)

| Field | Value |
|---|---|
| Case | `out/native_forces_smoke/teacher_case` |
| `backend_note` | `native_simpleFoam(sha1_preload)` |
| Cd / Cl / CmPitch | **0.145909166** / -0.175045426 / 0.049354074 |
| fidelity | **`L3_rans`** |
| Wall time | ~2 s (meshed path) |

Matches prior Docker-2412 Cd on the same tapered-prism mesh (**0.1459**).

### Docker fallback when native marked unhealthy

| Field | Value |
|---|---|
| `backend_note` | `docker_simpleFoam_native_forces_unhealthy` |
| Cd | **0.145909166** |
| fidelity | **`L3_rans`** |

### OPENSSL_CONF probes

Logs under `out/native_forces_probe/log.simpleFoam.{seclevel0,legacy,cipher_env,nullconf}` — all still `sha1` FATAL.

## Tests

- `tests/test_openfoam_l3.py` unit (`-m 'not integration'`): **13 passed**
- Integration smoke: **1 passed** (~2 s with native preload)

## Honesty / limits

- Preload makes **all** `IOstream::check` succeed while loaded (not name-filtered — ESI `fileName` ABI thwarted a targeted interpose). Scope risk by setting `LD_PRELOAD` only for teacher native FO solves.
- Coarse mesh, 3 laminar SIMPLE iters — exploratory ranking only; not ITTC / class.
- Rebuild `.so` after moving the tree: `gcc -shared -fPIC -O2 -o tools/foam_sha1_fix/libfoam_sha1_check_bypass.so tools/foam_sha1_fix/foam_sha1_check_bypass.c`
- Optional env: `YARD_SEA_FOAM_SHA1_PRELOAD=/path/to/libfoam_sha1_check_bypass.so`

## Re-run

```sh
cd /workspace/yard-sea-v0
export WM_PROJECT_DIR=/usr/share/openfoam FOAM_ETC=/usr/share/openfoam/etc
.venv/bin/python -c "
from yard_sea_v0.teachers.openfoam_l3 import run_teacher, detect_openfoam
print(detect_openfoam().to_dict())
r = run_teacher('out/sample_tapered_prism.stl', 0.2,
                'out/native_forces_smoke/rerun', L=120, B=20, T=8, timeout_s=180)
print(r['fidelity'], r['Cd'], r.get('backend_note'), r['skipped'])
"
```
