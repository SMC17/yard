# openfoam_hull_v0

Exploratory OpenFOAM case template for Yard-Sea-v0 **L3** resistance teacher.

- Geometry: `constant/triSurface/hull.stl` (copied + domain sized by `prepare_case`)
- Mesh: coarse `blockMesh` + `snappyHexMesh` (castellated+snap, no layers) → `hull` wall patch
- Solver: `potentialFoam -writep -withFunctionObjects` (fidelity **L3_potential**);
  fallback `simpleFoam` laminar, short `endTime` (**L3_rans**)
- Placeholders `__UX__`, `__MAG_U_INF__`, `__L_REF__`, `__A_REF__`,
  `__XMIN__`…`__NZ__`, `__LOCATION_IN_MESH__` filled by teacher
- Skip path: timeout / low disk → `L3_pending`

Not ITTC powering / not class / not production mesh QA.
