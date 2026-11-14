{-# OPTIONS --safe --without-K #-}

-- Exact test values for the programs of `OceanTriton.Space`: for each program, its buffers,
-- its parameters, a number of runs, and the exact result buffer that its meaning gives
-- (`repeat`). By `prop2D-run` and `model-run` these are `run2D` and `TimeLoop.run`.
-- `ocean-triton/check.py` runs the printed launches in order on the same inputs and compares.
--
-- A field is listed row by row, cell (x, y) at y * nx + x, as the printed kernels store it.
module OceanTriton.GridVectors where

open import Data.Integer using (+_)
open import Data.List as L using (List; []; _∷_; concat; upTo)
open import Data.Nat as ℕ using (ℕ; _*_; _%_)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.Rational using (ℚ; 0ℚ; _/_; _<?_)
open import Data.Rational.Show using () renaming (show to showℚ)
open import Data.String using (String; _++_; intersperse)
open import Data.Vec as V using (Vec; []; _∷_; lookup; toList; zipWith)
open import Relation.Nullary.Decidable using (from-yes)

open import OceanWaves.Dispersion using (Medium; padeModel)
open import OceanTriton.Grid hiding (nb; np)
open import OceanTriton.Space

private
  wave : ℕ → ℕ → ℕ → ℚ
  wave a b i = + ((a * i ℕ.+ b) % 13 ℕ.+ 1) / 8

  quoted : String → String
  quoted s = "\"" ++ s ++ "\""

  values : List ℚ → String
  values qs = "[" ++ intersperse ", " (L.map (λ q → quoted (showℚ q)) qs) ++ "]"

  -- A field on nx × ny cells, row by row.
  flat : ℕ → ℕ → Field → List ℚ
  flat nx ny F = concat (L.map (λ y → L.map (λ x → F x y) (upTo nx)) (upTo ny))

  json : ∀ {nb np} → String → ℕ → ℕ → ℕ → Vec String nb → Vec String np →
         Vec Field nb → Vec ℚ np → Field → String
  json name nx ny k bs ps fs qs out =
    "  " ++ quoted name ++ ": {\n" ++
    "    \"nx\": " ++ showℕ nx ++ ", \"ny\": " ++ showℕ ny ++ ", \"runs\": " ++ showℕ k ++ ",\n" ++
    "    \"buffers\": {" ++ intersperse ", "
       (toList (zipWith (λ b f → quoted b ++ ": " ++ values (flat nx ny f)) bs fs)) ++ "},\n" ++
    "    \"params\": {" ++ intersperse ", "
       (toList (zipWith (λ p q → quoted p ++ ": " ++ quoted (showℚ q)) ps qs)) ++ "},\n" ++
    "    \"expected\": " ++ values (flat nx ny out) ++ "\n  }"

-- 2-D propagation: a 9 × 7 periodic grid, cx = 2/5, cy = 1/3, three runs.
prop2DJson : String
prop2DJson = json "prop2d" nx ny runs ("F" ∷ "T" ∷ []) ("cx" ∷ "cy" ∷ []) bufs ps
  (lookup (repeat nx ny ps prop2DLaunches runs bufs) (result prop2D))
  where
  nx = 9
  ny = 7
  runs = 3
  ps = + 2 / 5 ∷ + 1 / 3 ∷ []
  bufs : Vec Field 2
  bufs = (λ x y → wave 7 3 (y * 9 ℕ.+ x)) ∷ (λ _ _ → 0ℚ) ∷ []

-- The model: 5 cells, 6 bins, in 2 m of water; Δt = 1/2, Δx = 3 (√(g h) Δt ≤ Δx), 20
-- bisection steps, the limiter L = 1/2, κ = 4 (the limiter clips at both bounds); two runs.
water : Medium
water = record { g = + 981 / 100 ; h = + 2 / 1
               ; g-pos = from-yes (0ℚ <? + 981 / 100) ; h-pos = from-yes (0ℚ <? + 2 / 1) }

modelConfig : ModelConfig
modelConfig = record
  { M = padeModel ; W = water ; nx = 5 ; nb = 6 ; σ = wave 3 2 ; Δt = + 1 / 2 ; Δx = + 3 / 1
  ; iters = 20 ; L = + 1 / 2 ; b = wave 2 1 ; g = wave 5 3 ; κ = + 4 / 1 }

modelJson : String
modelJson = json "model" 5 6 runs
  ("N" ∷ "P" ∷ "D" ∷ "beta" ∷ "gamma" ∷ "mu" ∷ []) ("dt" ∷ "L" ∷ "kappa" ∷ [])
  bufs (params0 modelConfig)
  (lookup (modelRun modelConfig runs bufs) (result model))
  where
  runs = 2
  bufs = buffers0 modelConfig (λ x j → wave 7 3 (j * 5 ℕ.+ x)) (λ _ _ → 0ℚ) (λ _ _ → 0ℚ)

gridVectors : String
gridVectors = "{\n" ++ prop2DJson ++ ",\n" ++ modelJson ++ "\n}\n"
