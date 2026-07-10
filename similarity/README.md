# yard-similarity-zig

Proof level: `unit-tested`

Geometric, kinematic, and dynamic similarity laws for model testing and
resistance extrapolation (Evans spiral / ITTC practice).

## What it does

- **`scale`** — λ = L_model / L_ship; linear, area, and volume scaling;
  `evaluateThreeRules` checks geometric, Froude kinematic, and Reynolds dynamic
  closure within configurable tolerances.
- **`froude`** — Fn = V / √(gL); speed from Fn; wave residual C_R copied
  model → ship under Froude scaling.
- **`reynolds`** — Rn = V L / ν and Reynolds scaling between model and ship.
- **`extrapolation`** — model C_T decomposition (C_F, C_R) and ship R_T, P_E
  from the ITTC-78 steps 4–7 subset; feeds `yard-ittc78-zig` powering chain.

## What it is not

Not a full ITTC-78 powering chain (see `yard-ittc78-zig`). Froude and Reynolds
cannot be matched simultaneously in the same fluid; viscous and wave effects are
treated separately per ITTC practice. Not a towing-tank test procedure or
model-ship correlation standard.

## Build and test

```
zig build test --summary all
```

## License

Apache-2.0. See `LICENSE`.