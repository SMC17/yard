# era

Historical constraint envelopes for the Yard Trials.

History supplies box rules; the physics modules stay era-agnostic. This
module encodes:

- **materials** — shipbuilding structural materials (oak, teak, wrought
  iron, riveted/mild/AH36 steel) with design allowable stresses, densities,
  moduli, availability years, and practical hull-length limits. Values are
  conservative design allowables with sources documented per entry (USDA
  Wood Handbook for timber; Victorian plate practice and IACS Grade
  yields for metals).
- **rules** — measurement and treaty rule functions that shaped real hulls:
  Builder's Old Measurement (the 1773 tonnage tax that made British hulls
  deep and narrow), the Moorsom system (1854), and the Washington Naval
  Treaty capital-ship caps (1922).
- **envelope** — six era envelopes (`age_of_sail`, `clipper`,
  `steam_transition`, `dreadnought`, `ww2`, `modern`) binding allowed
  materials, propulsion menus, and dimensional practice, plus a checker
  returning every violation of a design against an envelope.

```zig
const era = @import("yard_era");
var buf: [era.envelope.max_violations]era.envelope.Violation = undefined;
const violations = era.envelope.check(era.envelope.get(.age_of_sail), design, &buf);
```

Dimensional caps are era *practice* anchored to real ships (HMS Victory,
Great Republic, Great Eastern), not laws of physics; the mission runner
treats them as gates. Zero dependencies.

Proof level: unit-tested (static reference data + exact rule formulas).
