# Strip-path oracles — Yard-Sea-v0 bridge

**Status:** scaffold · 2026-09-10 (America/New_York)  
**Honesty:** not certification · not operational · not ITTC powering · not FAA/class

Yard-Sea-v0 is the **sea gym**. Strip is the **assurance / evidence** vocabulary.
These oracles were deferred on the integration board (“Later: OpenVSP + NeuralFoil + JSBSim”)
and are now stubbed so the air path can reuse the same teacher protocol.

## Assurance gates (link)

| Gate | Module | Role |
|------|--------|------|
| L0 reject | `hull.evaluate_l0` + monitors | Algebraic / hydrostatic filter |
| L1 rank | `resistance_l1` | Holtrop-simplified calm-water |
| **L1.5 wave** | `teachers.michell_l15` | Michell thin-ship Cw; Ship-D HP waterlines when vector given, else Wigley |
| L3 CFD | `teachers.openfoam_l3` | OpenFOAM snappy + forceCoeffs (`L3_rans` / `L3_potential` / `L3_pending`) |
| Strip overlay | `strip_assurance.strip_overlay` | ODD / claims / `not_certification` flags |
| Aero geometry | `teachers.openvsp_stub` | OpenVSP detect/run; VSPAERO CL/CD/CM when `vspaero` present |
| Aero VLM L1 | `teachers.vspaero_l1` | Thin wing VSPAEROComputeGeometry + VSPAEROSweep |
| Aero section | `teachers.neuralfoil_stub` | NeuralFoil Kulfan thin call |
| Aero FDM | `teachers.jsbsim_stub` | JSBSim integrate smoke |

`validation_gates` in the Strip overlay today track L0/L1/L2/L3 booleans.
L1.5 Michell and aero stubs attach as **teacher evidence** on gallery children /
standalone CLI — they do not claim a higher assurance level.

## Teacher protocol

See docstring in `yard_sea_v0/teachers/__init__.py`:

- `detect()` → availability (`.available`, `.to_dict()`, install hints)
- `run()` / `run_teacher()` → result dict; **skip cleanly** when deps missing

## Install hints

| Oracle | Light install? | Hint |
|--------|----------------|------|
| Michell L1.5 | **Yes (vendored)** | `vendor/shipd_upstream/ModifiedMichellCw.py` |
| NeuralFoil | **Yes** | `pip install neuralfoil` |
| JSBSim | **Yes** | `pip install jsbsim` |
| OpenVSP / VSPAERO | **Yes** (`vendor/openvsp/{vspscript,vspaero}`, Ubuntu 24.04 .deb) | See docs/OPENVSP_INSTALL.md |
| OpenFOAM L3 | **Yes (hybrid)** | Native 1912 mesh + Docker 2412 simpleFoam (see `out/forcecoeffs_result.md`) |

## CLI

```sh
PYTHONPATH=. python -m yard_sea_v0 run-search --parents 2 --steps 5 \
  --l15-michell --out out/michell_gallery
```

## Non-goals

Dual sea+air gyms at once · CREATE binaries · learning-in-ops · claiming cert.
