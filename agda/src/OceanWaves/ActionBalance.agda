{-# OPTIONS --safe --without-K #-}

-- The wave action balance equation and one model time step. Ported from
-- `ocean-waves/lean/OceanWaves/ActionBalance.lean`. The names follow Lean, with `-` for `_`.
--
-- WAVEWATCH III solves the action balance equation for the action density N = E / σ:
--
--     ∂N/∂t + ∇ₓ·((c_g + U) N) + ∂ₖ(k̇ N) + ∂_θ(θ̇ N) = S / σ
--
-- by fractional steps: propagation in geographic space, then in spectral space, then the local
-- source terms. Here, as in Lean: one geographic dimension, a fixed depth (so k̇ = θ̇ = 0), no
-- current and a periodic domain. A field F x j holds the action of bin j in cell x. One step:
--
-- 1. for each frequency σ_j, solve the dispersion relation for k_j (`waveNumber`) and get
--    c_g,j (`groupSpeed`);
-- 2. advect each bin with the Courant number μ_j = c_g,j Δt / Δx (`advectPeriodic`);
-- 3. apply the source step in each cell (`sourceStep`).
--
-- This module proves: every μ_j is in [0, 1] when g h Δt² ≤ Δx² (the depth-based CFL), for
-- any frequency grid and any number of bisection steps; propagation keeps the total action of
-- every bin; the full step keeps the spectrum non-negative; when the limiter does not clip,
-- the total action changes only through wind input and whitecapping; and the tabulated kernel
-- `stepFast` computes `step`.
--
-- Not stated, as in Lean: the continuous PDE, refraction and shoaling, currents, convergence
-- of the scheme, and anything about floating point.
--
-- Differences from Lean: `StepConfig.Local` states that the source rates agree bin by bin (an
-- equality of functions needs function extensionality, which --safe does not give).
module OceanWaves.ActionBalance where

open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_)
import Data.Nat.Properties as ℕP
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; :-_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

open import OceanWaves.Order
open import OceanWaves.Sums
open import OceanWaves.Advection
open import OceanWaves.Dispersion
open import OceanWaves.Bisection
open import OceanWaves.Sources

-- ---------------------------------------------------------------------------------------------
-- The discrete transport term is forward Euler of the flux-form equation

-- The semi-discrete right-hand side of ∂N/∂t + ∂(c_g N)/∂x = 0, with upwind fluxes and face
-- speeds cg.
transportRHS : ℚ → (ℕ → ℚ) → ℚ → (ℕ → ℚ) → ℕ → ℚ
transportRHS Δx cg b N i = - (cg (suc i) * N i - cg i * upstream b N i) /₀ Δx

-- `advect` with μ = c_g Δt / Δx is exactly one forward-Euler step of the semi-discrete
-- equation. This ties the kernel to the equation it solves.
advect-is-euler : ∀ Δt Δx (cg : ℕ → ℚ) b (N : ℕ → ℚ) i →
  advect (λ f → cg f * Δt /₀ Δx) b N i ≡ N i + Δt * transportRHS Δx cg b N i
advect-is-euler Δt Δx cg b N i =
  trans (advect-eq (λ f → cg f * Δt /₀ Δx) b N i)
    (solve 6 (λ n p c₁ c₀ t j →
        (con 1ℚ :- c₁ :* t :* j) :* n :+ c₀ :* t :* j :* p
        := n :+ t :* ((:- (c₁ :* n :- c₀ :* p)) :* j))
      refl (N i) (upstream b N i) (cg (suc i)) (cg i) Δt (inv₀ Δx))

-- ---------------------------------------------------------------------------------------------
-- One model step

-- Everything a time step needs. The source rates are functions of the local spectrum (a
-- cell's ℕ → ℚ), so any parameterisation can be plugged in.
record StepConfig : Set where
  field
    M     : TanhModel
    W     : Medium
    nx    : ℕ                      -- the number of cells
    nb    : ℕ                      -- the number of spectral bins
    σ     : ℕ → ℚ                  -- the frequency grid
    Δt    : ℚ
    Δx    : ℚ
    iters : ℕ                      -- bisection steps of the dispersion solver
    L     : ℚ                      -- the limiter bound
    β     : (ℕ → ℚ) → ℕ → ℚ
    γ     : (ℕ → ℚ) → ℕ → ℚ
    d     : (ℕ → ℚ) → ℕ → ℚ

module _ (C : StepConfig) where
  open StepConfig C

  k : ℕ → ℚ
  k j = waveNumber M W (σ j) iters

  cg : ℕ → ℚ
  cg j = groupSpeed M W (σ j) (k j)

  μ : ℕ → ℚ
  μ j = cg j * Δt /₀ Δx

  -- Step 2: propagate every bin.
  propagate : (ℕ → ℕ → ℚ) → ℕ → ℕ → ℚ
  propagate F x j = advectPeriodic nx (μ j) (λ x′ → F x′ j) x

  -- Step 3: the sources, cell by cell.
  sources : (ℕ → ℕ → ℚ) → ℕ → ℕ → ℚ
  sources F x j = sourceStep Δt L (β (F x)) (γ (F x)) nb (d (F x)) (F x) j

  -- One full time step.
  step : (ℕ → ℕ → ℚ) → ℕ → ℕ → ℚ
  step F = sources (propagate F)

  -- The total action in the domain.
  totalAction : (ℕ → ℕ → ℚ) → ℚ
  totalAction F = sumTo nx (λ x → sumTo nb (λ j → F x j))

  -- The conditions under which the theorems below hold.
  record Valid : Set where
    field
      σ-nonneg  : ∀ j → 0ℚ ≤ σ j
      Δt-nonneg : 0ℚ ≤ Δt
      Δx-pos    : 0ℚ < Δx
      -- The depth-based CFL condition: √(g h) Δt ≤ Δx, squared.
      cfl       : Medium.g W * Medium.h W * (Δt * Δt) ≤ Δx * Δx
      nx-pos    : 0 ℕ.< nx

  module _ (hC : Valid) where
    open Valid hC

    -- Every bin meets CFL under the depth-based condition.
    courant-bins : ∀ j → 0ℚ ≤ μ j × μ j ≤ 1ℚ
    courant-bins j = courant-le-one M W {σ = σ j} {k = k j} (σ-nonneg j) (waveNumber-pos M W (σ j) iters)
                       (waveNumber-upper M W (σ j) iters)
                       Δt-nonneg Δx-pos cfl

    -- Propagation keeps the action of every bin.
    propagate-bin-sum : ∀ F j → sumTo nx (λ x → propagate F x j) ≡ sumTo nx (λ x → F x j)
    propagate-bin-sum F j = go nx nx-pos
      where
      go : ∀ n → 0 ℕ.< n → sumTo n (λ x → advectPeriodic n (μ j) (λ x′ → F x′ j) x) ≡ sumTo n (λ x → F x j)
      go (suc m) _ = advectPeriodic-sum m (μ j) (λ x′ → F x′ j)

    -- Propagation keeps the total action.
    propagate-total : ∀ F → totalAction (propagate F) ≡ totalAction F
    propagate-total F =
      trans (sumTo-comm nx nb (λ x j → propagate F x j))
        (trans (sumTo-congr nb _ _ (λ j _ → propagate-bin-sum F j))
               (sym (sumTo-comm nx nb (λ x j → F x j))))

    -- Propagation keeps the spectrum non-negative.
    propagate-nonneg : ∀ F → (∀ x j → x ℕ.< nx → 0ℚ ≤ F x j) → ∀ x j → x ℕ.< nx → 0ℚ ≤ propagate F x j
    propagate-nonneg F hF x j hx =
      advect-nonneg nx _ _ (λ x′ → F x′ j) (λ _ _ → courant-bins j)
        (hF (nx ∸ 1) j (ℕP.∸-monoʳ-< {o = 0} (ℕ.s≤s ℕ.z≤n) nx-pos′)) (λ i hi → hF i j hi) x hx
      where
      nx-pos′ : 1 ℕ.≤ nx
      nx-pos′ = nx-pos

  -- The full step keeps the spectrum non-negative.
  step-nonneg : ∀ F x j → 0ℚ ≤ step F x j
  step-nonneg F x j =
    sourceStep-nonneg Δt L (β (propagate F x)) (γ (propagate F x)) nb (d (propagate F x)) (propagate F x) j

  -- The action budget of one step. If the limiter does not clip anywhere, the total action
  -- after the step is the total after propagation and the linear (wind and whitecapping)
  -- terms. The nonlinear transfer gives nothing.
  step-total : ∀ F →
    (∀ x → x ℕ.< nx → ∀ j → j ℕ.< nb →
       - linStep Δt (β (propagate F x) j) (γ (propagate F x) j) (propagate F x j)
           ≤ Δt * snl nb (d (propagate F x)) j
       × Δt * snl nb (d (propagate F x)) j ≤ L) →
    totalAction (step F)
      ≡ sumTo nx (λ x → sumTo nb (λ j →
          linStep Δt (β (propagate F x) j) (γ (propagate F x) j) (propagate F x j)))
  step-total F hfree = sumTo-congr nx _ _ (λ x hx →
    sourceStep-sum {Δt} {L} {β (propagate F x)} {γ (propagate F x)} {d (propagate F x)} {propagate F x} {nb}
      (hfree x hx))

  -- -------------------------------------------------------------------------------------------
  -- A fast step that agrees with `step`

  -- `step` with every intermediate field tabulated, so each value is computed once. This is
  -- the kernel to run; `step` is the one to reason about.
  stepFast : (ℕ → ℕ → ℚ) → ℕ → ℕ → ℚ
  stepFast F = tabulate2 nx nb (λ x j → sourceStep Δt L (β (P x)) (γ (P x)) nb (d (P x)) (P x) j)
    where
    μt = tabulate nb μ
    P  = tabulate2 nx nb (λ x j → advectPeriodic nx (μt j) (λ x′ → F x′ j) x)

  -- The source parameterisations read only the nb bins of a cell.
  Local : Set
  Local = ∀ N N′ → (∀ j → j ℕ.< nb → N j ≡ N′ j) →
    (∀ i → β N i ≡ β N′ i) × (∀ i → γ N i ≡ γ N′ i) × (∀ i → d N i ≡ d N′ i)

  propagate-row : ∀ F x → x ℕ.< nx → ∀ j → j ℕ.< nb →
    tabulate2 nx nb (λ x j → advectPeriodic nx (tabulate nb μ j) (λ x′ → F x′ j) x) x j ≡ propagate F x j
  propagate-row F x hx j hj =
    trans (tabulate2-eq nx nb _ x j hx hj)
          (cong (λ c → advectPeriodic nx c (λ x′ → F x′ j) x) (tabulate-eq nb μ j hj))

  private
    snl-cong : ∀ n {d₁ d₂ : ℕ → ℚ} → (∀ c → d₁ c ≡ d₂ c) → ∀ j → snl n d₁ j ≡ snl n d₂ j
    snl-cong n h j = sumTo-congr n _ _ (λ c _ → cong (λ u → gate (interior? n c) (u * quad c j)) (h c))

    sourceStep-cong : ∀ {β₁ β₂ γ₁ γ₂ d₁ d₂ N₁ N₂ : ℕ → ℚ} j →
      β₁ j ≡ β₂ j → γ₁ j ≡ γ₂ j → (∀ c → d₁ c ≡ d₂ c) → N₁ j ≡ N₂ j →
      sourceStep Δt L β₁ γ₁ nb d₁ N₁ j ≡ sourceStep Δt L β₂ γ₂ nb d₂ N₂ j
    sourceStep-cong {β₁} {β₂} {γ₁} {γ₂} {d₁} {d₂} {N₁} {N₂} j hb hg hd hn =
      cong₂ (λ s u → s + limit s L (Δt * u)) lin (snl-cong nb hd j)
      where
      lin : linStep Δt (β₁ j) (γ₁ j) (N₁ j) ≡ linStep Δt (β₂ j) (γ₂ j) (N₂ j)
      lin rewrite hb | hg | hn = refl

  -- The fast kernel computes exactly `step` on the grid.
  stepFast-eq : Local → ∀ F x j → x ℕ.< nx → j ℕ.< nb → stepFast F x j ≡ step F x j
  stepFast-eq hL F x j hx hj =
    trans (tabulate2-eq nx nb _ x j hx hj)
          (sourceStep-cong {β (P x)} {β (propagate F x)} {γ (P x)} {γ (propagate F x)}
             {d (P x)} {d (propagate F x)} {P x} {propagate F x} j (proj₁ hl j) (proj₁ (proj₂ hl) j) (proj₂ (proj₂ hl)) (hrow j hj))
    where
    P    = tabulate2 nx nb (λ x j → advectPeriodic nx (tabulate nb μ j) (λ x′ → F x′ j) x)
    hrow = propagate-row F x hx
    hl   = hL (P x) (propagate F x) hrow
