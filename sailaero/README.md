# sailaero

Sail aerodynamics: apparent wind, rig force coefficients, square-rig model,
and steady-state speed polars. One force model serves the Age-of-Sail
Trials missions and the interactive sailing demo.

```
zig build test    # 22 unit tests
zig build polar   # print reference sloop + tea-clipper speed polars
```

## Model

- **apparent** — exact apparent-wind vector math (AWS/AWA from TWS/TWA and
  boat speed).
- **coeffs** — fore-and-aft sail coefficients transcribed from ORC VPP
  Documentation 2023, Tables 5.1 (mainsail, kpm 0.01379) and 5.4
  (jib/genoa, kpj 0.016), low/high rigging sets, linear interpolation.
- **rig** — Hazen/IMS-style aggregation: area-weighted CL/CD0, quadratic
  viscous drag, induced drag from effective rig height, drive/side
  projection.
- **squarerig** — braced-yard flat-plate approximation (CL = cl_peak sin 2a,
  CD = cd0 + 1.9 sin^2 a) with a 30-degree brace limit and cd0 = 0.40
  carrying the standing-rigging windage of a full rig. Documented
  approximation; clipper passage-data validation is a later rung.
- **polar** — solves drive(v) = R(v) + R_leeway(v) with apparent-wind
  feedback. Hull resistance is a caller-supplied table; leeway-induced drag
  reacts the rig side force through lifting-line with the free-surface
  mirror (effective span 2 x draft). This term is what produces the upwind
  dead zone — without it any rig "sails" at absurd pointing angles.

## Reference polars (zig build polar)

The 10 m sloop peaks near 75 deg TWA and beats effectively at 40-50 deg;
the 3000 m2 square-rigged clipper cannot make way above ~80 deg to the true
wind and is fastest on a broad reach — consistent with the historical "six
points off the wind" limit, currently slightly conservative (v0 shows no
way at 75 deg true where a crack clipper could still make some).

Proof level: unit-tested. Zero yard dependencies (hull stays abstract);
couples to fossen-6dof and the mission runner in later rungs.
