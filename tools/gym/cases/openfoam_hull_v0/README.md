# openfoam_hull_v0

Exploratory OpenFOAM case template for Yard-Sea-v0 **L3** resistance teacher.

- Solver intent: `potentialFoam` smoke → later `simpleFoam` + `forceCoeffs`
- Geometry: `constant/triSurface/hull.stl` (copied by `prepare_case`)
- Placeholders `__UX__`, `__MAG_U_INF__`, `__L_REF__`, `__A_REF__` filled by teacher
- Fidelity: **L3_pending** until a real FOAM run produces forceCoeffs

Not ITTC powering / not class / not production mesh QA.
