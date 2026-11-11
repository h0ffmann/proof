{-# OPTIONS --safe --without-K #-}

-- Concrete numbers for the spectral grid, the unstructured mesh and the radiation stress,
-- checked by Agda: `refl` on a closed term, `from-yes` on a decidable relation.
module WaveTheory.GridExamples where

open import Data.Integer using () renaming (+_ to ℤ+)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _-_; _*_; _≤_; _<_; _≤?_; _<?_)
open import Relation.Nullary.Decidable using (from-yes; True; toWitness)
open import Data.Product using (_,_)
open import Data.Unit using (tt)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanWaves.Order
open import OceanWaves.Sums
open import WaveTheory.SpectralGrid
open import WaveTheory.Unstructured
open import WaveTheory.RadiationStress

-- ---------------------------------------------------------------------------------------------
-- A WAVEWATCH III frequency grid: XFR = 1.1, SIG(1) = 1, four bins (m = 2)

xfr : ℚ
xfr = ℤ+ 11 / 10

grid-σ3 : sig 1ℚ xfr 3 ≡ ℤ+ 1331 / 1000
grid-σ3 = refl

-- The widths: 1/20, 0.1155, 0.12705 and 0.0605 (the last is one-sided).
grid-dsii : dsii 2 1ℚ xfr 0 + dsii 2 1ℚ xfr 1 + dsii 2 1ℚ xfr 2 + dsii 2 1ℚ xfr 3
          ≡ ℤ+ 331 / 1000
grid-dsii = refl

-- `dsii-total` gives the same number for every grid: SIG(4) - SIG(1) = 0.331.
grid-dsii-total : sumTo 4 (dsii 2 1ℚ xfr) ≡ sig 1ℚ xfr 3 - sig 1ℚ xfr 0
grid-dsii-total = dsii-total 2 1ℚ {xfr} (λ ())

-- The grid is not arithmetic: 2 σ(1) = 2.2 < σ(0) + σ(2) = 2.21.
grid-not-arith : 2ℚ * sig 1ℚ xfr 1 < sig 1ℚ xfr 0 + sig 1ℚ xfr 2
grid-not-arith = from-yes (2ℚ * sig 1ℚ xfr 1 <? sig 1ℚ xfr 0 + sig 1ℚ xfr 2)

-- An isotropic spreading over 4 directions gives each one a quarter.
iso-weight : D (isotropic 3) 0 ≡ ℤ+ 1 / 4
iso-weight = refl

-- ---------------------------------------------------------------------------------------------
-- A mesh of two triangles: the square 0-1-2-3 cut along the diagonal 0-2

square : List Edge
square = edge 0 1 (ℤ+ 1 / 4) ∷ edge 1 2 (ℤ+ 1 / 4) ∷ edge 0 3 (ℤ+ 1 / 4)
       ∷ edge 3 2 (ℤ+ 1 / 4) ∷ edge 0 2 (ℤ+ 1 / 4) ∷ edge 2 0 (ℤ+ 1 / 8) ∷ []

pulse : ℕ → ℚ
pulse 0 = lit 4
pulse _ = 0ℚ

-- One step spreads the pulse at node 0 evenly over the four nodes.
square-step : meshStep square pulse 0 ≡ 1ℚ
square-step = refl

square-step-1 : meshStep square pulse 1 ≡ 1ℚ
square-step-1 = refl

square-step-2 : meshStep square pulse 2 ≡ 1ℚ
square-step-2 = refl

square-step-3 : meshStep square pulse 3 ≡ 1ℚ
square-step-3 = refl

square-in-mesh : InMesh 4 square
square-in-mesh =
  lt 0 , lt 1 , lt 1 , lt 2 , lt 0 , lt 3 , lt 3 , lt 2 , lt 0 , lt 2 , lt 2 , lt 0 , tt
  where
  lt : ∀ m → {{_ : True (m ℕ.<? 4)}} → m ℕ.< 4
  lt m {{p}} = toWitness p

-- The total stays 4 after any number of steps, by `meshRun-total`.
square-total : ∀ k → sumTo 4 (meshRun square k pulse) ≡ lit 4
square-total k = meshRun-total 4 square k pulse square-in-mesh

-- Node 0 sends 3/4 of its content, every other node at most 1/4: the CFL condition holds.
square-cfl : CFLMesh square
square-cfl 0 = from-yes (outRate square 0 ≤? 1ℚ)
square-cfl 1 = from-yes (outRate square 1 ≤? 1ℚ)
square-cfl 2 = from-yes (outRate square 2 ≤? 1ℚ)
square-cfl 3 = from-yes (outRate square 3 ≤? 1ℚ)
square-cfl (suc (suc (suc (suc j)))) = from-yes (0ℚ ≤? 1ℚ)

-- ---------------------------------------------------------------------------------------------
-- Radiation stress: E = 16, n = 3/4, direction (3/5, 4/5)

d345 : Direction
d345 = dir (ℤ+ 3 / 5) (ℤ+ 4 / 5) refl

rs-xx : Sxx (lit 16) (ℤ+ 3 / 4) d345 ≡ ℤ+ 208 / 25
rs-xx = refl

rs-xy : Sxy (lit 16) (ℤ+ 3 / 4) d345 ≡ ℤ+ 144 / 25
rs-xy = refl

rs-yy : Syy (lit 16) (ℤ+ 3 / 4) d345 ≡ ℤ+ 292 / 25
rs-yy = refl

-- The trace is E (3n - 1) = 20 and the determinant E² (2n - 1/2)(n - 1/2) = 64.
rs-det : Sxx (lit 16) (ℤ+ 3 / 4) d345 * Syy (lit 16) (ℤ+ 3 / 4) d345
       - Sxy (lit 16) (ℤ+ 3 / 4) d345 * Sxy (lit 16) (ℤ+ 3 / 4) d345 ≡ lit 64
rs-det = refl
