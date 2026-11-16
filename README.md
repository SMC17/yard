# yard

[![CI](https://github.com/SMC17/yard/actions/workflows/ci.yml/badge.svg)](https://github.com/SMC17/yard/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Zig: 0.16](https://img.shields.io/badge/Zig-0.16-orange.svg)](https://ziglang.org/)

Naval architecture and marine engineering in Zig.

Evidence-bearing marine engineering and ship-hydrodynamics tooling in Zig.

72 primitive modules plus integrated design, fleet, competition, and viewer
packages in one repository. Consolidated 2026-07-07 from the individual
yard-*-zig repositories; each module keeps its own `build.zig`, source,
and test suite.

| module | scope |
|---|---|
| [ais](ais/) | AIS vessel-tracking decode |
| [anchor](anchor/) | anchor holding power and ground-tackle sizing |
| [auv](auv/) | autonomous underwater vehicle dynamics |
| [azipod](azipod/) | azimuth-thruster (azipod) propulsion |
| [benchmark](benchmark/) | standard-hull validation harness + tank extrapolation |
| [bem](bem/) | boundary-element-method ship hydrodynamics |
| [bow](bow/) | bow form and added resistance in waves |
| [cargo](cargo/) | cargo stowage and loading computations |
| [cathodic](cathodic/) | cathodic corrosion protection |
| [cavitation](cavitation/) | propeller cavitation analysis |
| [cii](cii/) | IMO Carbon Intensity Indicator (CII) |
| [collision](collision/) | collision damage and risk analysis |
| [combat](combat/) | naval combat-system modeling |
| [compose](compose/) | multi-module naval workflows (spiral, DP, seakeeping) |
| [coupled-motions](coupled-motions/) | coupled 6-DOF ship motions |
| [csr-buckling](csr-buckling/) | CSR buckling assessment |
| [csr-fatigue](csr-fatigue/) | CSR fatigue assessment |
| [csr](csr/) | IACS Common Structural Rules |
| [deck](deck/) | deck structural design |
| [deicing](deicing/) | marine de-icing and winterization |
| [drydock](drydock/) | dry-docking operations |
| [dynpos](dynpos/) | dynamic positioning (DP) capability |
| [eedi](eedi/) | IMO Energy Efficiency Design Index (EEDI) |
| [engine](engine/) | marine engine performance |
| [flettner](flettner/) | Flettner rotor-sail thrust |
| [fmi](fmi/) | FMI co-simulation interface |
| [fleet](fleet/) | generic multi-vessel design, preliminary scantlings, and hierarchical formation control |
| [foilcraft](foilcraft/) | hydrofoil-craft dynamics |
| [fossen-6dof](fossen-6dof/) | Fossen 6-DOF maneuvering model |
| [fueltank](fueltank/) | fuel-tank sloshing and management |
| [grounding](grounding/) | grounding damage and residual stability |
| [helideck](helideck/) | helideck design and loads |
| [hess-smith-3d](hess-smith-3d/) | Hess-Smith 3D panel method |
| [historical-conflict](historical-conflict/) | governed 1778-only aggregate conflict screening and replay |
| [hydro](hydro/) | ship hydrostatics |
| [icebreaker](icebreaker/) | icebreaking resistance |
| [irf](irf/) | radiation impulse-response functions |
| [ittc78](ittc78/) | ITTC-1978 performance prediction |
| [jacket](jacket/) | offshore jacket structure |
| [keel](keel/) | keel and appendage design |
| [launch](launch/) | ship-launch dynamics |
| [load-line](load-line/) | load line and freeboard (ICLL) |
| [maneuvering](maneuvering/) | ship maneuvering prediction |
| [mass](mass/) | mass and weight estimation |
| [mooring](mooring/) | mooring-system analysis |
| [naval-arch](naval-arch/) | naval-architecture core primitives |
| [noise](noise/) | underwater radiated-noise estimation |
| [pipeline](pipeline/) | subsea pipeline engineering |
| [port-engineering](port-engineering/) | port civil engineering |
| [port-logistics](port-logistics/) | port logistics and throughput |
| [propulsion](propulsion/) | propulsion-system modeling |
| [rao-spectrum](rao-spectrum/) | response-amplitude-operator spectra |
| [recycling](recycling/) | ship recycling — Hong Kong Convention 2009 + EU SRR |
| [resistance](resistance/) | ITTC-57 friction line and resistance prediction |
| [roro](roro/) | RoRo / ferry vehicle-deck loading |
| [routing](routing/) | spherical-geodesy voyage routing |
| [saildrone](saildrone/) | unmanned wind-powered surface vehicle dynamics |
| [savitsky](savitsky/) | Savitsky planing-hull lift |
| [seakeeping](seakeeping/) | wave spectra and seakeeping response |
| [similarity](similarity/) | geometric/kinematic/dynamic scaling + ITTC-78 extrapolation |
| [spiral](spiral/) | Evans 1959 design spiral orchestrator |
| [shaft](shaft/) | marine shafting torsional vibration |
| [shipyard-mgmt](shipyard-mgmt/) | shipyard production scheduling |
| [sloshing](sloshing/) | linear-potential-flow tank sloshing |
| [springing](springing/) | hull-girder springing vibration |
| [stability](stability/) | small-angle intact stability |
| [stir](stir/) | IMO Second-Generation Intact Stability (STIR) Level 1 |
| [strength](strength/) | IACS Unified Requirements hull-girder strength |
| [strip-theory](strip-theory/) | frequency-domain strip-theory heave |
| [submarine](submarine/) | pressure-hull collapse (von Mises) and hydrostatics |
| [terminal](terminal/) | container-terminal berth allocation and service |
| [towing-tank](towing-tank/) | towing-tank model-test data reduction |
| [tug](tug/) | escort-tug performance |
| [vimstab](vimstab/) | container-stack lateral load and stability |
| [viz](viz/) | deterministic SVG visualization (GZ, Pareto, hull profiles) |
| [viz-vulkan](viz-vulkan/) | deterministic 3D fleet frames plus optional native Vulkan queue/readback path |
| [windaero](windaero/) | ship wind-coefficient estimation |

## Platform

See [PLATFORM.md](PLATFORM.md) for the composition layer, dataset pipeline, eval harness,
and extension architecture (spreadsheet-style naval engineering).

### Open design stack

| Surface | Ownership |
|---|---|
| [`mission/`](mission/) | Single-vessel physics gates and deterministic voyage evaluation |
| [`era/`](era/) | Historical material, propulsion, dimension, tonnage, and treaty envelopes |
| [`sailaero/`](sailaero/) + [`econ/`](econ/) | Sail polars and voyage economics for historical missions |
| [`sailmission/`](sailmission/) | Era-gated passages and the empirical Mercury fleet backend |
| [`fleet/`](fleet/) | Generic mixed-vessel compilation, scantling screens, and safe formation control |
| [`trials/`](trials/) | GitHub-native PR submissions, CI re-execution, JSONL results, and frontier pages |
| [`arena/`](arena/) | Fleet/agent competition protocol, replay chains, signed seasons, hard screening, RNG contract, and scorecard binding |
| [`arena/web/`](arena/web/) | Dependency-free local ship builder, Pareto board, and mission evidence UI |
| [`arena/hosted/`](arena/hosted/) | Pre-deployment signed-season Worker, isolated agent/evaluator Sandboxes, Queue/DO coordination, R2/D1 leaderboard |
| [`historical-conflict/`](historical-conflict/) | Fail-closed 1778 policy, deterministic aggregate fleet outcomes, and Arena replay chains |
| [`dynpos/`](dynpos/) | Versioned Zig telemetry protocol and NATS publisher for the OTP fleet coordinator |

The client builder is a preflight and artifact-authoring surface. The Mercury
reference result is regenerated by `yard-mercury` from the licensed CLIWOC
route ensemble, then bound to a replay head before Arena scores it.

## Quickstart

```sh
# Requires Zig 0.16.0
git clone https://github.com/SMC17/yard.git
cd yard
zig build test-core      # hydro + stability + compose + spiral + benchmark
zig build test-all       # all 72 primitive-module suites
zig build test-frontier  # Mercury + Arena + fleet + telemetry + viewer + governed 1778 conflict
zig build run-example    # canonical box-barge intact stability
zig build run-spiral     # Evans design spiral (Wigley)
zig build run-spiral-kcs # Evans spiral with KCS tank C_T ingest
zig build run-benchmark  # 18-case hull validation harness
zig build run-sim-suite  # DP + irregular waves + Pareto
zig build run-fleet-viewer # formation dynamics -> deterministic 3D fleet frame
zig build run-historical-conflict # governed 1778 aggregate screening scenario
python tools/portfolio_audit/audit.py --strict
(cd arena && scripts/verify.sh) # regenerate/score Mercury + verify replay/signatures
(cd arena/hosted && npm run check && npm run build) # hosted contracts + dry-run image/Worker build
python tools/dataset/generate.py --samples 100 --output tools/dataset/out/seed.jsonl
```

| Layer | Path | Purpose |
|-------|------|---------|
| Primitives | 72 modules below | Narrow, tested kernels |
| Composition | `compose/`, `examples/` | Multi-module workflows |
| Intelligence | `tools/oracle/`, `tools/dataset/`, `tools/eval/` | SFT data + eval |
| Docs | `docs/` | Architecture + deep dives |

License: Apache-2.0 (unified across all modules).
