# OpenVSP install (Yard-Sea-v0 Strip)

Goal: get `vspscript` / `vsp` so `yard_sea_v0.teachers.openvsp_stub` can
`detect()` and run a thin AngelScript vehicle (not full VSPAERO yet).

## What works on this box (Debian 13 / trixie, 2026-09-10)

**Working approach:** download the official **Ubuntu 24.04 amd64 `.deb`**,
extract it (no `dpkg -i` required), install a few shared libs, point the stub
at `vendor/openvsp`.

| Path | Result |
|------|--------|
| `apt install openvsp` | **None** — not in Debian/Ubuntu apt |
| `pip install openvsp` | **None** — not on PyPI |
| conda / mamba | Not installed on this box; no lightweight package used |
| Docker image | `docker` binary present; daemon permission denied for `box` user |
| Ubuntu **26.04** `.deb` | Needs `libc6 >= 2.43` and `libpython3.14` — **too new** for Debian 13 (glibc 2.41) |
| Ubuntu **24.04** `.deb` | **Works** (glibc >= 2.38 satisfied); Python bindings need `libpython3.12` (not on this host — CLI only) |
| AppImage / GitHub release zip | No official Linux AppImage; Linux builds are `.deb` via openvsp.org |

## One-shot install

```bash
./tools/install_openvsp.sh
```

Or manually:

1. Download: https://openvsp.org/download.php → **OpenVSP 3.51.3 Ubuntu 24.04**
2. `dpkg-deb -x OpenVSP-*-Ubuntu-24.04_amd64.deb /tmp/ov`
3. `mv /tmp/ov/opt/OpenVSP repo/vendor/openvsp`
4. `sudo apt-get install -y libcminpack1 libglew2.2 libglu1-mesa`
5. Smoke via stub:

```bash
cd /path/to/yard-sea-v0
python -c "from yard_sea_v0.teachers import openvsp_stub as o; print(o.detect()); print(o.run())"
```

Override deb URL if needed:

```bash
OPENVSP_DEB_URL="https://openvsp.org/download.php?file=zips/current/linux/OpenVSP-3.51.3-Ubuntu-24.04_amd64.deb" \
  ./tools/install_openvsp.sh
```

### Headless note

- Prefer **`vspscript`** (no GUI). Plain `vsp` / `vsp -batch` can hang waiting for a display.
- `vspscript` may exit nonzero after a successful `WriteVSPFile` (teardown);
  the stub judges success by stdout markers + `.vsp3` size.

### Python `import openvsp`

The 24.04 package ships `python/openvsp` built against **`libpython3.12.so.1.0`**.
Debian 13 here only has Python 3.13 — bindings are **not** imported unless you
install a matching libpython3.12 (Ubuntu package) or use the 26.04 build on a
newer glibc host. CLI path is enough for the current stub.

## Blockers (if reinstall fails)

1. **glibc** — do not use the Ubuntu 26.04 `.deb` on Debian 13 (needs 2.43).
2. **Missing `.so`** — `libcminpack.so.1`, `libGLEW.so.2.2`, `libGLU.so.1`
   (`apt install libcminpack1 libglew2.2 libglu1-mesa`).
3. **No pip wheel** — do not expect `pip install openvsp`.
4. **Docker** — needs usable daemon + an image that packages OpenVSP (none used here).
5. **Building from source** — heavy (CMake + many deps); prefer the `.deb` extract.

## Stub behavior

- `detect()` → PATH `vspscript`/`vsp`, else `vendor/openvsp/vspscript`.
- `run()` → minimal AngelScript: `ClearVSPModel` + `POD` + `WriteVSPFile`.
- `CL`/`CD`/`CM` remain `None` until a VSPAERO adapter is wired.
