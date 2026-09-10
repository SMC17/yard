# OpenVSP result (Yard-Sea-v0 Strip)

**Date:** 2026-09-10 17:33 EDT
**Status:** **PASS** — real `detect()` / thin `run()` via vendored `vspscript`

## Outcome

| Item | Result |
|------|--------|
| `vspscript` / `vsp` CLI | **Yes** at `vendor/openvsp/` (OpenVSP 3.51.3, Ubuntu 24.04 `.deb` extract) |
| `detect()` | Finds `vendor/openvsp/vspscript` |
| `run()` thin call | `ClearVSPModel` + `POD` + `WriteVSPFile` → `.vsp3` (~61 KB) |
| `CL` / `CD` / `CM` | Still `None` (VSPAERO adapter not wired) |
| `import openvsp` | **No** — `_vsp.so` needs `libpython3.12`; host is Python 3.13 |
| Tests | `tests/test_aero_stubs.py` — **8 passed** |

## Install path that worked

1. Downloaded `OpenVSP-3.51.3-Ubuntu-24.04_amd64.deb` from https://openvsp.org/download.php
2. `dpkg-deb -x` → `vendor/openvsp`
3. `apt install libcminpack1 libglew2.2 libglu1-mesa`
4. Smoke: `vspscript -script …` (prefer over GUI `vsp`, which can hang headless)

Reinstall: `./tools/install_openvsp.sh` — details in `docs/OPENVSP_INSTALL.md`.

## Paths that failed / skipped

| Approach | Blocker |
|----------|---------|
| apt / pip | No `openvsp` package |
| Ubuntu 26.04 `.deb` | Needs glibc ≥ 2.43 + libpython3.14 (Debian 13 has glibc 2.41) |
| conda | Not available on box |
| Docker | Daemon permission denied for `box` |
| AppImage | Not published by upstream |
| Python bindings | ABI mismatch (3.12 `.so` vs host 3.13) |

## Notes

- `vspscript` sometimes exits nonzero after successful `WriteVSPFile` (teardown); stub success = stdout markers + `.vsp3` size.
- Vendor tree is ~175 MB under `vendor/openvsp` (full upstream payload including python/docs/matlab).
- No GitHub push performed.
