# Triangle grids for spectral wave models

How to build a triangle (unstructured) grid for WAVEWATCH III (WW3) with the size rules that Aron
Roland and his co-authors use, what Agda proves about those rules and about WW3's explicit scheme on
the grid, and how the same kind of grid serves different kinds of wave forecasting.

Triangle grids in WW3 are Aron Roland's work, with Fabrice Ardhuin; at NOAA, Ali Abdolali led the
domain decomposition and the implicit scheme on them. The owner's own WW3 work is ww3-gpu; his six
works are marola ([10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155)), ww3-gpu
([10.5281/zenodo.23221351](https://doi.org/10.5281/zenodo.23221351)), picasso
([10.5281/zenodo.23311208](https://doi.org/10.5281/zenodo.23311208)), closed source
([10.5281/zenodo.23333656](https://doi.org/10.5281/zenodo.23333656)), marola-bench
([10.5281/zenodo.23352633](https://doi.org/10.5281/zenodo.23352633)) and nashkell, the open book
([10.5281/zenodo.23356739](https://doi.org/10.5281/zenodo.23356739)).

```sh
just agda                # the 13 statements in agda/src/Grids/, the 4 counterexamples as witnesses
just grids               # the room mesh as NOTE lines, against the numbers below (checks/room-mesh.sh)
```

## Sources, read on 2026-11-09

- **[A26]** Abdolali, A., Hesser, T. J., Roland, A., Schönau, M., Honegger, D. A., Smith, J. M.,
  Michaud, H. and Centurioni, L. (2026). Advancing multi-scale wave modeling: Global and coastal
  applications during the 2022 Atlantic hurricane season. *Ocean Modelling* 199, 102623.
  [10.1016/j.ocemod.2025.102623](https://doi.org/10.1016/j.ocemod.2025.102623). Section 5.2 holds
  the size rules below.
- **[G25]** Gaffet, A., Bertin, X., Sous, D., Michaud, H., Roland, A. and Cordier, E. (2025). A new
  global high-resolution wave model for the tropical ocean using WAVEWATCH III version 7.14.
  *Geoscientific Model Development* 18, 1929–1946.
  [10.5194/gmd-18-1929-2025](https://doi.org/10.5194/gmd-18-1929-2025).
- **[RA14]** Roland, A. and Ardhuin, F. (2014). On the developments of spectral wave models:
  numerics and parameterizations for the coastal ocean. *Ocean Dynamics* 64, 833–846.
  [10.1007/s10236-014-0711-z](https://doi.org/10.1007/s10236-014-0711-z).
- **WW3** at metocean/WW3 `92e2cf66` (tag `7.14.mos-92e2cf6`), the pin of
  [chaceon](https://github.com/h0ffmann/chaceon); `port-audit/.cache/WW3` after
  `tools/port-audit/run.sh coverage`.

## How to build the grid

A26 sets one local minimum spacing per criterion and keeps the smallest: "The final resolution at
any given location is determined as the smallest value among these minimums". In order:

1. **A floor.** "A minimum grid spacing of 5 km (node-to-node edge length) is defined to capture
   essential geometries."
2. **Depth, through the group velocity.** "the depth-dependent resolution is calculated as the
   product of the time step and group velocity", with "an implicit time step of 600 s" and
   "The model configuration's minimum frequency of 0.035 Hz is used to calculate the group
   velocity". The lowest frequency is the fastest wave, so this rule makes the slowest-to-resolve
   wave cross one cell per step. For orientation (arithmetic of the linear dispersion relation,
   not from A26 ⚠): in shallow water `c_g = sqrt(g h)`, so 10 m of water gives about 9.9 m/s and
   5.9 km; in deep water `c_g = g / (4 π f)` = 22.3 m/s at 0.035 Hz, so 13.4 km. At 0.035 Hz the
   deep-water limit holds only beyond about 640 m of depth (half of `L0 = g / (2 π f²)` ≈ 1.27 km).
3. **Distance to the coast.** "the mesh generator calculates the distance from the coastline,
   assigning higher resolution to nearshore areas"; "A cutoff distance of 100 km is applied", and
   "regions beyond this distance adopt the user-defined deepwater resolution". A26 gives no number
   for that deep-water resolution.
4. **Slope.** "A depth gradient cutoff of 0.1 is applied, with steeper slopes enforcing the
   minimum grid spacing". Steep slopes refract waves strongly, and the refraction is resolved
   only on fine cells.
5. **Gradation.** "a mesh size growth rate of 30% is applied to prevent abrupt changes in
   resolution between adjacent elements". Going from 5 km to 30 km then takes at least seven
   neighbour steps, since 1.3⁶ × 5 km = 24.1 km and 1.3⁷ × 5 km = 31.4 km.

A26 names no generator and no angle criterion; G25 built its grid with the Surface-water Modeling
System (SMS), "with a resolution ranging from 50 km in the deep ocean to about 1 km around most
islands". Whatever generator is used, it needs the five rules above as its size function, and the
grid goes to `ww3_grid` as a Gmsh file with grid type `'UNST'`.

## What Agda proves

[`agda/src/Grids/`](../agda/src/Grids.agda) (`SizeRule`, `Courant`, `Iter`), over exact rationals, under
`--safe`. A counterexample is a witness that the statement fails. Z3 checked the same statements,
in Scala, until 2026-11-11.

| Statement | Result |
|---|---|
| The size is never below the 5 km floor; a slope over 0.1 gives the floor; otherwise the size is the smaller of the depth and coast minimums | proved |
| With the depth rule `h_d = 600 s × c_g`, every cell has a Courant number `c_g × 600 s / h` of at least 1, and above 1 wherever another rule is finer | proved; the explicit CFL condition at 600 s fails (counterexample), which is why A26 steps implicitly |
| Six 30% steps from 5 km stay below 30 km; seven reach it | proved; counterexample |
| WW3's explicit N-scheme sub-step count `ITER` covers the CFL number up to `THR8` | proved, see below |

**The explicit scheme's sub-steps.** WW3's default unstructured scheme is the explicit N-scheme:
`EXPFSN = .TRUE.` and the five others false (`model/src/w3gridmd.F90:2405-2410`), and a grid of type
`UNST` must select exactly one (`:2447-2462`). [RA14] chose "the explicit N-scheme on triangle
meshes because it is faster than higher-order explicit schemes", and notes that "the numerical
efficiency of explicit methods is limited by the strict CFL criterion". WW3 meets the criterion
by splitting the global step: each node's largest stable step is `SI / KKSUM`
(`model/src/w3profsmd.F90:644`), `CFLXY = DT / DTMAXGL` over the nodes (`:648`), and `ITER`
rounds `CFLXY` up unless its fractional part is below `THR8 = TINY(1d0)` (`:561`, `:649-656`).
Agda proves `ITER ≥ CFLXY − THR8` and `ITER ≥ CFLXY` whenever the fractional part is 0 or above
`THR8`. It also has the edge as a witness: a fractional part in `(0, THR8]` rounds down, and a CFL number of
at most `THR8` gives `ITER = 0`, so the loop `DO IT = 1, ITER` (`:663`) does not run and the
spectrum does not move. `THR8` is about 2.2 × 10⁻³⁰⁸, so the edge is a curiosity, not a defect a
run would meet.

The fewer sub-steps per global step, the cheaper an explicit run; the depth rule of step 2 is the
rule that keeps them near one at the scheme's time step. A grid built for a 600 s implicit step
and run with the explicit scheme at 600 s needs `ITER > 1` wherever a cell is finer than the depth
rule: near the coast and on slopes.

## The room's mesh, measured

[piabrota/room](https://github.com/piabrota/room)'s ▲ grid view draws a demonstration mesh of the
Brazilian coast (`scripts/grid.mjs` at `66e38a7`): coast nodes every 9 km, then four hexagonal
lattices in distance bands out to 550 km, spaced by `9 + 61 × min(1, d / 550)^1.4` km, joined by
Delaunay. Its sea is an estimate from the wind, not a WW3 run. Against A26's rules (`tools/room-mesh/run.sh`,
NOTE lines, in `bash checks/room-mesh.sh`):

- The coast spacing, 9 km, is above the 5 km floor.
- The lattices are 9.68, 13.47, 25.38 and 51.52 km, so the steps between bands are ratios of 1.39,
  1.88 and 2.03: every band boundary grows faster than 30%. A grid for a WW3 run would need a
  size function graded node by node, as the rules above say, not bands.
- It has no depth or slope criterion, since the view has no bathymetry yet.

## Using the grid in wave forecasting

| Kind of forecast | What the triangle grid gives | Scheme and step | Source |
|---|---|---|---|
| Global, with coasts and islands resolved | one grid from 50 km in the open ocean to about 1 km around islands, refined to 100 m where buoys sit, in place of nested regular grids | implicit, one 800 s step with no splitting | [G25] |
| Hurricane and multi-scale coastal | the five rules above: fine where depth, coast and slope ask, coarse elsewhere, with domain decomposition across processors | implicit, 600 s | [A26] |
| Nearshore and surf zone | "a 110,000 node unstructured mesh with an alongshore resolution of 300 to 500 m"; below 100 m the schemes need further work | explicit N-scheme or implicit | [RA14] |
| A small explicit run, for learning or a demonstration | a few thousand nodes, the default `EXPFSN` scheme, `ITER` sub-steps where cells are fine | explicit, sub-stepped (`w3profsmd.F90:648-663`) | WW3 |

The trade between the two schemes is stated in [RA14]: implicit methods "do not have a strict
Courant-Friedrichs-Levy (CFL)-like stability criterion", while "This explicit scheme also gives
smaller errors than its implicit version". A forecast with a fixed wall-clock budget and a grid
graded down to a few kilometres takes the implicit step; a study that needs the smallest
propagation error on a modest grid can afford the explicit sub-steps.

What is not here ⚠: no WW3 run on such a grid, no measured skill and no timing. The Agda statements
check the rules' arithmetic and WW3's sub-step count, not a forecast.
