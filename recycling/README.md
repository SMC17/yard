# yard-recycling-zig

Proof level: `unit-tested`

Ship-recycling kernel covering Hong Kong Convention 2009 + EU SRR
1257/2013 applicability, Inventory of Hazardous Materials (IHM)
concentration checks, and material-recovery valorisation.

## Modules

- `hkc` — Capacity utilisation, HKC entry-into-force year (2025),
  EU SRR applicability gate, USD proceeds.
- `ihm` — 12 HKC Appendix 1+2 hazardous materials with max allowable
  fractions; per-entry concentration verdict; total mass; failing-
  entry count.
- `recovery` — 7 material categories with LDT fractions (steel plate
  0.55, steel section 0.25, non-ferrous 0.04, cables 0.02, machinery
  0.10, timber 0.01, hazardous 0.03); valorisation and hazardous
  disposal cost.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 37/37 tests passed`.

## References

- IMO. *Hong Kong International Convention for the Safe and
  Environmentally Sound Recycling of Ships* (2009).
- European Parliament Regulation 1257/2013 (Ship Recycling
  Regulation).
- ILO. *Safety and health in shipbreaking: Guidelines for Asian
  countries and Turkey* (2004).

Apache-2.0.
