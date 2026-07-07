# Reasoning Quality Rubric (Dataset Filter)

Score each generated reasoning trace 0–5 per dimension. **Keep only records scoring ≥4 on all dimensions.**

## Dimensions

### 1. Formula Citation (weight: 2×)
- **5:** Every step cites the exact formula with variable definitions
- **3:** Formulas present but incomplete variable naming
- **1:** Hand-wavy "calculate GM" without formula
- **0:** Wrong formula cited confidently

### 2. Free-Surface Correction (weight: 2×)
- **5:** i_FS = lb³/12, GG' = (ρ_fluid/ρ_sw)·i_FS/V, applied before GZ
- **3:** Correction applied but formula incomplete
- **1:** Mentioned but not computed
- **0:** Omitted when tanks present

### 3. Assumption Flagging (weight: 1×)
- **5:** Explicit B/(2T) check, wall-sided vs small-angle decision stated
- **3:** Partial flagging
- **0:** No assumption checks

### 4. IS Code Threshold Application (weight: 2×)
- **5:** All six thresholds with correct values and computed margins
- **3:** Thresholds listed but one wrong value
- **0:** Wrong regulatory reference or invented thresholds

### 5. Numerical Consistency (weight: 3×)
- **5:** All numbers match oracle within 1e-4
- **3:** Minor rounding differences
- **0:** Any number contradicts oracle

## Automated Gates (hard reject)

1. Oracle recomputation mismatch on any answer field
2. Missing `flags` when assumptions apply
3. Duplicate instruction hash (dedup)
4. `overall` contradicts individual criterion verdicts

## Gap-Audit Criteria

A record qualifies for the gap-audit set only if:

1. At least one frontier model fails it with strong CoT prompting
2. Oracle passes 100%
3. Failure mode is catalogued (formula mix-up, missed correction, etc.)