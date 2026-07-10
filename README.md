# yard

Naval architecture and marine engineering in Zig.

75 modules, one repository. Consolidated 2026-07-07 from the individual
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
| [foilcraft](foilcraft/) | hydrofoil-craft dynamics |
| [fossen-6dof](fossen-6dof/) | Fossen 6-DOF maneuvering model |
| [fueltank](fueltank/) | fuel-tank sloshing and management |
| [grounding](grounding/) | grounding damage and residual stability |
| [helideck](helideck/) | helideck design and loads |
| [hess-smith-3d](hess-smith-3d/) | Hess-Smith 3D panel method |
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
| [viz-vulkan](viz-vulkan/) | scene-graph renderer (headless SVG; Vulkan stub) |
| [windaero](windaero/) | ship wind-coefficient estimation |

## Platform

See [PLATFORM.md](PLATFORM.md) for the composition layer, dataset pipeline, eval harness,
and extension architecture ("naval Excel").

```sh
zig build test-core      # hydro + stability + compose + spiral + benchmark
zig build run-example    # canonical box-barge intact stability
zig build run-spiral     # Evans design spiral (Wigley)
zig build run-spiral-kcs # Evans spiral with KCS tank C_T ingest
zig build run-benchmark  # 18-case hull validation harness
zig build run-sim-suite  # DP + irregular waves + Pareto
python tools/portfolio_audit/audit.py --strict
python tools/dataset/generate.py --samples 100 --output tools/dataset/out/seed.jsonl
```

| Layer | Path | Purpose |
|-------|------|---------|
| Primitives | 72 modules below | Narrow, tested kernels |
| Composition | `compose/`, `examples/` | Multi-module workflows |
| Intelligence | `tools/oracle/`, `tools/dataset/`, `tools/eval/` | SFT data + eval |
| Docs | `docs/` | Architecture + deep dives |

License: Apache-2.0 (unified across all modules).
