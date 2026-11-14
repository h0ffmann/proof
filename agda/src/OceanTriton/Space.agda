{-# OPTIONS --safe --without-K #-}

-- Milestone M2 of ocean-triton/PLAN.md: 2-D propagation and the model's time loop as programs of
-- kernel launches, proved equal to the specification.
--
-- Two programs:
--
--   - `prop2D`: on a periodic nx × ny grid, a sweep in x (buffer F to T), then a sweep in y (T to
--     F). Its meaning, run k times, is `WaveTheory.Propagation2D.run2D` for every k, as an
--     equality of fields (`prop2D-run`), so `run2D-total`, `run2D-nonneg` and `run2D-le` hold
--     for it.
--   - `model`: one step of `OceanWaves.ActionBalance` on nx cells and nb bins. Propagation with
--     each bin's Courant number (N to P), the exchange amounts d = κ P (P to D), then the source
--     step with S_nl as a stencil on D (to N). Its meaning is `ActionBalance.step` for every
--     input (`model-step`), and run k times it is `WaveTheory.TimeLoop.run` (`model-run`), so
--     `run-nonneg` holds for it.
--
-- The model's source rates are a special case of `StepConfig`: the wind input b and the
-- dissipation g are given per bin, and the exchange amount is κ times the action. The general
-- `StepConfig` takes functions of the local spectrum, which a kernel cannot read as data.
module OceanTriton.Space where

open import Data.Fin using (Fin; zero; #_)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import OceanWaves.Order using (2ℚ)
open import OceanWaves.Sums using (sumTo-congr)
open import OceanWaves.Sources using (snl; linStep; limit; gate; interior?; quad)
open import OceanWaves.Dispersion using (TanhModel; Medium)
open import OceanWaves.ActionBalance as AB using (StepConfig)
import WaveTheory.TimeLoop as TL
open import WaveTheory.Propagation2D as P2 using (sweepX; sweepY; step2D; run2D; total2D; OnGrid; Courant)
open import OceanTriton.Step using (snl-stencil)
open import OceanTriton.Grid hiding (nb; np)

-- ---------------------------------------------------------------------------------------------
-- The kernels

sweepXK : Kernel2
sweepXK = record
  { name = "sweep_x" ; na = 1 ; ns = 1 ; arrays = "F" ∷ [] ; scalars = "c" ∷ []
  ; body = cell (# 0) ⊕ par (# 0) ⊗ west (# 0) ⊖ par (# 0) ⊗ cell (# 0)
  ; doc = "the upwind sweep in x on a periodic grid (WaveTheory.Propagation2D.sweepX)" }

sweepYK : Kernel2
sweepYK = record
  { name = "sweep_y" ; na = 1 ; ns = 1 ; arrays = "F" ∷ [] ; scalars = "c" ∷ []
  ; body = cell (# 0) ⊕ par (# 0) ⊗ south (# 0) ⊖ par (# 0) ⊗ cell (# 0)
  ; doc = "the upwind sweep in y on a periodic grid (WaveTheory.Propagation2D.sweepY)" }

-- y is the spectral bin j; mu holds bin j's Courant number in every cell.
propagateK : Kernel2
propagateK = record
  { name = "propagate" ; na = 2 ; ns = 0 ; arrays = "N" ∷ "mu" ∷ [] ; scalars = []
  ; body = cell (# 0) ⊕ cell (# 1) ⊗ west (# 0) ⊖ cell (# 1) ⊗ cell (# 0)
  ; doc = "every bin advected in x with its Courant number (OceanWaves.ActionBalance.propagate)" }

exchangeK : Kernel2
exchangeK = record
  { name = "exchange" ; na = 1 ; ns = 1 ; arrays = "N" ∷ [] ; scalars = "kappa" ∷ []
  ; body = cell (# 0) ⊗ par (# 0)
  ; doc = "the exchange amounts of S_nl, d = kappa N" }

sourcesK : Kernel2
sourcesK = record
  { name = "sources" ; na = 4 ; ns = 2
  ; arrays = "beta" ∷ "gamma" ∷ "N" ∷ "d" ∷ [] ; scalars = "dt" ∷ "L" ∷ []
  ; body = lin ⊕ max (neg lin) (min (par (# 1)) (par (# 0) ⊗ snl2))
  ; doc = "the source step in every cell, S_nl as a stencil along the bins (OceanWaves.ActionBalance.sources)" }
  where
  lin snl2 : Expr2 4 2
  lin  = cell (# 2) ⊗ (con 1ℚ ⊕ par (# 0) ⊗ cell (# 0)) ⊘ (con 1ℚ ⊕ par (# 0) ⊗ cell (# 1))
  snl2 = giny (# 3) right ⊕ giny (# 3) left ⊖ con 2ℚ ⊗ giny (# 3) here

kernels2 : List Kernel2
kernels2 = sweepXK ∷ sweepYK ∷ propagateK ∷ exchangeK ∷ sourcesK ∷ []

-- The sweeps, kernel by kernel: refl at every cell.
sweepXK-sound : ∀ nx ny c F x y → eval2 (body sweepXK) (store2 nx ny (F ∷ []) (c ∷ [])) x y ≡ sweepX nx c F x y
sweepXK-sound nx ny c F x y = refl

sweepYK-sound : ∀ nx ny c F x y → eval2 (body sweepYK) (store2 nx ny (F ∷ []) (c ∷ [])) x y ≡ sweepY ny c F x y
sweepYK-sound nx ny c F x y = refl

-- ---------------------------------------------------------------------------------------------
-- 2-D propagation: two launches per step

prop2DLaunches : List (Launch 2 2)
prop2DLaunches =
  launch sweepXK (# 0 ∷ []) (# 0 ∷ []) (# 1) ∷
  launch sweepYK (# 1 ∷ []) (# 1 ∷ []) (# 0) ∷ []

prop2D : Program
prop2D = record
  { name = "prop2d" ; nb = 2 ; np = 2 ; buffers = "F" ∷ "T" ∷ [] ; params = "cx" ∷ "cy" ∷ []
  ; launches = prop2DLaunches ; result = # 0
  ; doc = "2-D upwind propagation by dimensional splitting (WaveTheory.Propagation2D.run2D)" }

private
  vec2-eta : ∀ {A : Set} (v : Vec A 2) → v ≡ lookup v (# 0) ∷ lookup v (# 1) ∷ []
  vec2-eta (a ∷ b ∷ []) = refl

-- One run of the program is one split step, for every field: an equality of fields.
prop2D-step : ∀ nx ny cx cy F T →
  lookup (steps nx ny (cx ∷ cy ∷ []) prop2DLaunches (F ∷ T ∷ [])) (# 0) ≡ step2D nx ny cx cy F
prop2D-step nx ny cx cy F T = refl

-- k runs are k split steps.
prop2D-run : ∀ nx ny cx cy k F T →
  lookup (repeat nx ny (cx ∷ cy ∷ []) prop2DLaunches k (F ∷ T ∷ [])) (# 0) ≡ run2D nx ny cx cy k F
prop2D-run nx ny cx cy zero    F T = refl
prop2D-run nx ny cx cy (suc k) F T =
  trans (cong (λ v → lookup (steps nx ny (cx ∷ cy ∷ []) prop2DLaunches v) (# 0)) (vec2-eta r))
        (cong (step2D nx ny cx cy) (prop2D-run nx ny cx cy k F T))
  where r = repeat nx ny (cx ∷ cy ∷ []) prop2DLaunches k (F ∷ T ∷ [])

private
  prop2DRun : ℕ → ℕ → ℚ → ℚ → ℕ → Field → Field → Field
  prop2DRun nx ny cx cy k F T = lookup (repeat nx ny (cx ∷ cy ∷ []) prop2DLaunches k (F ∷ T ∷ [])) (# 0)

-- The theorems of Propagation2D, for the program's meaning.
prop2D-total : ∀ nx ny cx cy k F T →
  total2D nx ny (prop2DRun (suc nx) (suc ny) cx cy k F T) ≡ total2D nx ny F
prop2D-total nx ny cx cy k F T =
  trans (cong (total2D nx ny) (prop2D-run (suc nx) (suc ny) cx cy k F T)) (P2.run2D-total nx ny cx cy k F)

prop2D-nonneg : ∀ nx ny cx cy → Courant cx → Courant cy → ∀ k F T → OnGrid nx ny (0ℚ ≤_) F →
  OnGrid nx ny (0ℚ ≤_) (prop2DRun (suc nx) (suc ny) cx cy k F T)
prop2D-nonneg nx ny cx cy hx hy k F T hF =
  subst (OnGrid nx ny (0ℚ ≤_)) (sym (prop2D-run (suc nx) (suc ny) cx cy k F T))
        (P2.run2D-nonneg nx ny cx cy hx hy k F hF)

prop2D-le : ∀ nx ny cx cy M → Courant cx → Courant cy → ∀ k F T → OnGrid nx ny (_≤ M) F →
  OnGrid nx ny (_≤ M) (prop2DRun (suc nx) (suc ny) cx cy k F T)
prop2D-le nx ny cx cy M hx hy k F T hF =
  subst (OnGrid nx ny (_≤ M)) (sym (prop2D-run (suc nx) (suc ny) cx cy k F T))
        (P2.run2D-le nx ny cx cy M hx hy k F hF)

-- ---------------------------------------------------------------------------------------------
-- The model step: three launches

-- Buffers: N (the action), P (after propagation), D (the exchange amounts), beta, gamma, mu.
-- Parameters: dt, L, kappa.
modelLaunches : List (Launch 6 3)
modelLaunches =
  launch propagateK (# 0 ∷ # 5 ∷ []) [] (# 1) ∷
  launch exchangeK  (# 1 ∷ []) (# 2 ∷ []) (# 2) ∷
  launch sourcesK   (# 3 ∷ # 4 ∷ # 1 ∷ # 2 ∷ []) (# 0 ∷ # 1 ∷ []) (# 0) ∷ []

model : Program
model = record
  { name = "model" ; nb = 6 ; np = 3
  ; buffers = "N" ∷ "P" ∷ "D" ∷ "beta" ∷ "gamma" ∷ "mu" ∷ [] ; params = "dt" ∷ "L" ∷ "kappa" ∷ []
  ; launches = modelLaunches ; result = # 0
  ; doc = "one model step: propagation, exchange amounts, sources (OceanWaves.ActionBalance.step)" }

-- What the model computes: a StepConfig with rates given per bin and d = κ N.
record ModelConfig : Set where
  field
    M     : TanhModel
    W     : Medium
    nx nb : ℕ
    σ     : ℕ → ℚ
    Δt Δx : ℚ
    iters : ℕ
    L     : ℚ
    b g   : ℕ → ℚ
    κ     : ℚ

module _ (MC : ModelConfig) where
  open ModelConfig MC

  config : StepConfig
  config = record
    { M = M ; W = W ; nx = nx ; nb = nb ; σ = σ ; Δt = Δt ; Δx = Δx ; iters = iters ; L = L
    ; β = λ _ → b ; γ = λ _ → g ; d = λ N c → N c * κ }

  -- The buffers the host fills once: the rates and each bin's Courant number, in every cell.
  buffers0 : Field → Field → Field → Vec Field 6
  buffers0 N P D = N ∷ P ∷ D ∷ (λ _ j → b j) ∷ (λ _ j → g j) ∷ (λ _ j → AB.μ config j) ∷ []

  params0 : Vec ℚ 3
  params0 = Δt ∷ L ∷ κ ∷ []

  modelRun : ℕ → Vec Field 6 → Vec Field 6
  modelRun = repeat nx nb params0 modelLaunches

  -- One run of the program is one model step, at every cell and bin.
  model-step : ∀ N P D x j →
    lookup (steps nx nb params0 modelLaunches (buffers0 N P D)) (# 0) x j ≡ AB.step config N x j
  model-step N P D x j =
    cong (λ s → linStep Δt (b j) (g j) (Pr x j) + limit (linStep Δt (b j) (g j) (Pr x j)) L (Δt * s))
         (sym (snl-stencil nb (λ c → Pr x c * κ) j))
    where Pr = AB.propagate config N

  -- The step depends on the field only through its values.
  private
    propagate-cong : ∀ F F′ → (∀ x j → F x j ≡ F′ x j) → ∀ x j → AB.propagate config F x j ≡ AB.propagate config F′ x j
    propagate-cong F F′ h zero    j = cong₂ (λ a u → a + AB.μ config j * u - AB.μ config j * a) (h 0 j) (h (nx ∸ 1) j)
    propagate-cong F F′ h (suc x) j = cong₂ (λ a u → a + AB.μ config j * u - AB.μ config j * a) (h (suc x) j) (h x j)

    step-cong : ∀ F F′ → (∀ x j → F x j ≡ F′ x j) → ∀ x j → AB.step config F x j ≡ AB.step config F′ x j
    step-cong F F′ h x j =
      cong₂ (λ p s → linStep Δt (b j) (g j) p + limit (linStep Δt (b j) (g j) p) L (Δt * s))
        (hp x j)
        (sumTo-congr nb _ _ (λ c _ → cong (λ q → gate (interior? nb c) (q * κ * quad c j)) (hp x c)))
      where hp = propagate-cong F F′ h

    -- The host's buffers stay as they were: only N, P and D are written.
    keep : Vec Field 6 → Vec Field 6
    keep v = buffers0 (lookup v (# 0)) (lookup v (# 1)) (lookup v (# 2))

    run-keep : ∀ k N P D → modelRun k (buffers0 N P D) ≡ keep (modelRun k (buffers0 N P D))
    run-keep zero    N P D = refl
    run-keep (suc k) N P D =
      trans (cong (steps nx nb params0 modelLaunches) ih)
            (cong (λ v → keep (steps nx nb params0 modelLaunches v)) (sym ih))
      where ih = run-keep k N P D

  -- k runs of the program are k model steps.
  model-run : ∀ k N P D x j → lookup (modelRun k (buffers0 N P D)) (# 0) x j ≡ TL.run config k N x j
  model-run zero    N P D x j = refl
  model-run (suc k) N P D x j =
    trans (cong (λ v → lookup (steps nx nb params0 modelLaunches v) (# 0) x j) (run-keep k N P D))
      (trans (model-step (lookup r (# 0)) (lookup r (# 1)) (lookup r (# 2)) x j)
             (step-cong (lookup r (# 0)) (TL.run config k N) (model-run k N P D) x j))
    where r = modelRun k (buffers0 N P D)

  -- The spectrum the program computes stays non-negative for every run length.
  model-nonneg : ∀ k N P D → (∀ x j → 0ℚ ≤ N x j) → ∀ x j → 0ℚ ≤ lookup (modelRun k (buffers0 N P D)) (# 0) x j
  model-nonneg k N P D hN x j =
    subst (0ℚ ≤_) (sym (model-run k N P D x j)) (TL.run-nonneg config k N hN x j)

programs : List Program
programs = prop2D ∷ model ∷ []
