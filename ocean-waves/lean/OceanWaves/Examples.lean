import OceanWaves.ActionBalance

/-!
# Examples

`#eval` outputs from the kernels, in exact `Rat` arithmetic, printed as
decimals. `Float` appears only here, as a reference value next to a `Rat` result
(`Float.tanh` and a Newton solve with the true `tanh`); no theorem is about `Float`.
`native_decide` is allowed only in this file, for concrete counterexamples.
-/

namespace OW.Examples
open OW

/-- Print a `Rat` with `d` decimals (truncated toward −∞). -/
def showQ (q : Rat) (d : Nat := 4) : String :=
  let s := if q < 0 then "-" else ""
  let a := if q < 0 then -q else q
  let ip := a.floor
  let scale : Nat := 10 ^ d
  let fp := ((a - ip) * scale).floor.toNat
  let fs := toString fp
  s ++ toString ip ++ "." ++ String.mk (List.replicate (d - fs.length) '0') ++ fs

def showL (l : List Rat) (d : Nat := 4) : String := toString (l.map (showQ · d))

def toF (q : Rat) : Float := Float.ofInt q.num / Float.ofNat q.den

/-! ## 1. The rational `tanh` model against `Float.tanh` -/

#eval [1/2, 1, 2, 3, 4].map fun (x : Rat) => (showQ (padeT x), (toF x).tanh)

/-! ## 2. Dispersion: a 10 s wave in 10 m and in 1000 m of water -/

def g : Rat := 981 / 100
def shallow : Medium := ⟨g, 10, by unfold g; grind, by grind⟩
def deep : Medium := ⟨g, 1000, by unfold g; grind, by grind⟩
/-- `σ = 2π / 10 s`, with `π ≈ 355/113`. -/
def σ10 : Rat := 2 * (355 / 113) / 10

/-- Reference: Newton on `g k tanh(k h) = σ²` with the true `tanh`, in `Float`. -/
def kNewton (σ h : Float) : Float := Id.run do
  let gF := 9.81
  let mut k := σ * σ / gF
  for _ in [0:50] do
    let t := (k * h).tanh
    let f := gF * k * t - σ * σ
    let df := gF * t + gF * k * h * (1 - t * t)
    k := k - f / df
  return k

-- k (rad/m), c and c_g (m/s) from the 30-iteration bisection kernel, and the
-- `Float` reference wavenumber with the true `tanh`.
#eval
  let k := waveNumber padeModel shallow σ10 30
  (showQ k 5, showQ (phaseSpeed σ10 k), showQ (groupSpeed padeModel shallow σ10 k),
    kNewton (toF σ10) 10)

#eval
  let k := waveNumber padeModel deep σ10 30
  (showQ k 5, showQ (phaseSpeed σ10 k), showQ (groupSpeed padeModel deep σ10 k),
    kNewton (toF σ10) 1000)

-- Shallow-water speed √(g h) for h = 10 m: c above must not exceed it.
#eval (toF (g * 10)).sqrt

/-! ## 3. Advection: a bump goes round a periodic grid, total kept -/

def bump : Nat → Rat := fun i => if i = 2 then 4 else if i = 3 then 2 else 0

#eval showL (toList 8 (advectPeriodicN 8 (1/2) 0 bump)) 3
#eval showL (toList 8 (advectPeriodicN 8 (1/2) 4 bump)) 3
#eval (sumTo 8 bump, sumTo 8 (advectPeriodicN 8 (1/2) 4 bump))

/-- Above CFL (`μ = 3/2`) one step already makes a negative value. -/
theorem cfl_violation_negative : advectPeriodic 8 (3/2) bump 2 < 0 := by native_decide

/-! ## 4. Sources: semi-implicit vs explicit Euler on strong whitecapping -/

-- Δt γ = 3, no wind: semi-implicit damps to N/4; explicit Euler goes negative.
#eval (showQ (linStep 1 0 3 1), showQ (eulerStep 1 0 3 1))

theorem euler_negative : eulerStep 1 0 3 1 < 0 := by native_decide

-- Wind growth rate β (1/s) for u* = 0.5 m/s along the wind, in deep water.
-- The 10 s wave (c ≈ 15.6 m/s) outruns the wind: 28 u*/c < 1, so β = 0
-- (`windRate_zero`). A 5 s wave (c ≈ 7.8 m/s) grows.
def wind : WindParams := ⟨1/4, 1225/1025000, 1/2, by grind, by grind⟩
def σ5 : Rat := 2 * σ10
#eval
  let k10 := waveNumber padeModel deep σ10 30
  let k5 := waveNumber padeModel deep σ5 30
  (showQ (windRate wind σ10 (phaseSpeed σ10 k10) 1) 8,
   showQ (windRate wind σ5 (phaseSpeed σ5 k5) 1) 8)

/-! ## 5. Nonlinear transfer: DIA-like exchange amounts, action and energy kept -/

def spec5 : Nat → Rat := fun i => [1, 3, 5, 3, 2, 1].getD i 0
/-- Exchange amount at centre `c` with the DIA shape `N_c² (N₋ + N₊) − 2 N₋ N_c N₊`. -/
def diaAmount (N : Nat → Rat) (c : Nat) : Rat :=
  (N c * N c * (N (c - 1) + N (c + 1)) - 2 * N (c - 1) * N c * N (c + 1)) / 100

#eval showL (toList 6 (snl 6 (diaAmount spec5))) 3
#eval (sumTo 6 (snl 6 (diaAmount spec5)),
       sumTo 6 (fun j => (1 + (j : Rat) / 10) * snl 6 (diaAmount spec5) j))

/-! ## 6. One full model step: 6 cells × 4 frequencies, 10 m depth -/

/-- DIA-shaped exchange that reads only bins below `nb`. -/
def diaLocal (nb : Nat) (N : Nat → Rat) (c : Nat) : Rat :=
  if c + 1 < nb then diaAmount N c / 10 else 0

def cfg : StepConfig where
  M := padeModel
  W := shallow
  nx := 6
  nb := 4
  σ := fun j => (2 + j) / 5
  Δt := 100
  Δx := 1000
  iters := 12
  L := 1
  β := fun _ _ => 1 / 1000
  γ := fun _ _ => 1 / 2000
  d := diaLocal 4

def F0 : Nat → Nat → Rat := fun x j => if x = 1 then (4 - j : Rat) else 0

-- Courant numbers of the 4 bins (all in [0, 1], as `courant_bins` promises)
#eval showL (toList 4 cfg.μ)
-- Cell 1 before the step; cells 1 and 2 after it
#eval
  let F1 := stepFast cfg F0
  (showL (toList 4 (F0 1)), showL (toList 4 (F1 1)), showL (toList 4 (F1 2)))
-- Total action before and after (here wind input > whitecapping, so it grows)
#eval
  let F1 := stepFast cfg F0
  (showQ (totalAction cfg F0), showQ (totalAction cfg F1))

/-- The configuration meets the depth-based CFL condition, so every theorem in
`ActionBalance` applies to it. -/
theorem cfg_valid : cfg.Valid where
  σ_nonneg := fun j => by
    show (0 : Rat) ≤ (2 + (j : Rat)) / 5
    exact div_nonneg' (by have := Rat.natCast_nonneg (a := j); grind) (by grind)
  Δt_nonneg := by show (0 : Rat) ≤ 100; grind
  Δx_pos := by show (0 : Rat) < 1000; grind
  cfl := by show g * 10 * (100 * 100) ≤ (1000 : Rat) * 1000; unfold g; grind
  nx_pos := by decide

/-- Its source terms read only the 4 bins, so `stepFast` computes `step`. -/
theorem cfg_local : cfg.Local := by
  intro N N' h
  have h : ∀ j, j < 4 → N j = N' j := h
  refine ⟨rfl, rfl, ?_⟩
  funext c
  show diaLocal 4 N c = diaLocal 4 N' c
  unfold diaLocal diaAmount
  split
  · rw [h c (by omega), h (c - 1) (by omega), h (c + 1) (by omega)]
  · rfl

end OW.Examples
