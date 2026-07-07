# yard-csr-zig

Proof level: `unit-tested`

yard-csr-zig is a Zig 0.16 IACS Common Structural Rules section-modulus
check across multiple loading conditions. Stress sigma = |M_sw + M_wv|
/ Z_net is compared against the UR S4 permissible stress 175 / k for
each loading condition; an aggregate verdict requires all conditions
to pass.

## What it does

- `section_check.SteelGrade` enum (mild, ht32, ht36, ht40) with UR S4
  material factor k.
- `section_check.LoadingCondition` typed input (still-water and wave
  bending moments hog and sag, corrosion deduction).
- `section_check.Section` typed input (gross section modulus, steel
  grade).
- `section_check.permissibleStressMpa(grade)` returns 175 / k.
- `section_check.evaluate(condition, section)` returns a typed
  `Result` with per-mode stress, permissible, margins, and verdicts.
- `section_check.aggregateVerdict(results)` returns pass iff every
  condition's overall verdict is pass.

## What it is not (v0.0.0)

- No full CSR-BC&OT bulk-carrier / oil-tanker rule book
  reproduction.
- No yielding + buckling + fatigue combined-load check.
- No SOLAS II-1 probabilistic damage stability.
- No corrosion-deduction calculation from plate-wastage geometry
  (caller supplies the delta_Z in m^3).
- No shear-stress check.
- No wave-bending-moment computation (compose with
  yard-strength-zig externally for UR S11 M_wv).

## Composition with yard-strength-zig

Typical workflow:

```zig
const strength = @import("yard_strength");
const csr = @import("yard_csr");

const M_wv_hog = try strength.ur_s11.waveMomentHog(200.0, 32.0, 0.85, 1.0);
const M_wv_sag = try strength.ur_s11.waveMomentSag(200.0, 32.0, 0.85, 1.0);

const conditions = [_]csr.section_check.LoadingCondition{
    .{ .name = "Full load departure", .M_sw_hog_kNm = ..., .M_sw_sag_kNm = ...,
       .M_wv_hog_kNm = M_wv_hog, .M_wv_sag_kNm = M_wv_sag,
       .delta_Z_corrosion_m3 = 0.5 },
    .{ .name = "Ballast", .M_sw_hog_kNm = ..., ... },
};
const section: csr.section_check.Section = .{ .Z_gross_m3 = 20.0, .grade = .mild };
var results: [conditions.len]csr.section_check.Result = undefined;
for (conditions, 0..) |c, i| {
    results[i] = try csr.section_check.evaluate(c, section);
}
const overall = csr.section_check.aggregateVerdict(&results);
```

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 11/11 tests passed`.

## Validation

- UR S4 material factors match the IACS table to f64 round-off.
- A bulker condition with M_sw_hog ~ 1e6 kN*m + M_wv_hog ~ 2e6 kN*m
  and Z = 19.5 m^3 net gives sigma_hog ~ 153.8 MPa, below the mild
  permissible 175 MPa: PASS.
- An overloaded condition with sigma_hog ~ 267 MPa exceeds 175 MPa:
  FAIL.
- Higher-strength steel (HT40) has higher permissible stress and
  same physical stress.
- aggregateVerdict returns FAIL if any condition fails.
- margin_hog = sigma_perm - sigma_hog.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IACS Common Structural Rules for Bulk Carriers and Oil Tankers
  (CSR-BC&OT), 2014 harmonized rev.
- IACS Unified Requirement S11 (Longitudinal Strength).
- IACS Unified Requirement S4 (Material factor table).
- Hughes, O.F. and Paik, J.K. (2010), *Ship Structural Analysis and
  Design*, SNAME, Ch. 4.
- Codex cross-references at
  `~/codex/concepts/iacs-ur-s11-longitudinal-strength.md`.

## License

Apache-2.0.
