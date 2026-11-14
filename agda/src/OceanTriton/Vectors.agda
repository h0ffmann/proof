{-# OPTIONS --safe --without-K #-}

-- Exact test values for the printed Triton kernels: for each kernel, an input on n lanes and the
-- exact rational output that its meaning gives (`runMap`, `runReduce`). By the soundness
-- theorems of `OceanTriton.Kernels` these are the outputs of the `OceanWaves` kernels.
-- `ocean-triton/check.py` runs the Triton kernels on the same inputs and compares.
--
-- The inputs reach both branches of every choice: k h on both sides of 3 in the Padé tanh, wind
-- input on and off, the limiter active and inactive, and a zero divisor in the group velocity
-- (k = 0 at lane 0, where /₀ gives 0).
module OceanTriton.Vectors where

import Data.Integer
open import Data.Integer using (ℤ; +_; _-_)
open import Data.List as L using (List; []; _∷_; concat)
open import Data.Nat as ℕ using (ℕ; zero; suc; _*_; _%_)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _≤?_)
open import Relation.Nullary.Decidable using (from-yes)
open import Data.Rational.Show using () renaming (show to showℚ)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.String using (String; _++_; intersperse; unlines)
open import Data.Vec as V using (Vec; []; _∷_; toList; zipWith)

open import OceanWaves.Order using (lit)
open import Relation.Binary.PropositionalEquality using (refl)
open import OceanWaves.Sources using (snl)
open import OceanWaves.Sums using () renaming (toList to sample)
open import OceanTriton.Expr
open import OceanTriton.Kernels
open import OceanTriton.Step using (snlK; sourceSnlK; sxxK; sxyK; syyK; wavenumberK; stressStore)
open import WaveTheory.RadiationStress using (Direction; dir)
open import OceanWaves.Dispersion using (Medium)

-- The number of lanes: more than one block of 16, and not a multiple of it.
lanes : ℕ
lanes = 40

-- A positive pattern (a i + b mod 13 + 1) / 8, between 1/8 and 7/4.
wave : ℕ → ℕ → ℕ → ℚ
wave a b i = + ((a * i ℕ.+ b) % 13 ℕ.+ 1) / 8

-- A signed pattern ((a i + b mod 9) - 4) / 4, between -1 and 1.
signed : ℕ → ℕ → ℕ → ℚ
signed a b i = (+ ((a * i ℕ.+ b) % 9) - + 4) / 4

-- i / d.
ramp : ℕ → ℕ → ℚ
ramp d i = + i / suc d

-- n between 1/2 (deep water) and 1 (shallow water).
half : ℕ → ℕ → ℕ → ℚ
half a b i = + ((a * i ℕ.+ b) % 9 ℕ.+ 9) / 18

-- Directions on the unit circle from Pythagorean triples, one per lane in turn.
pyth : ℕ → Direction
pyth zero                   = dir (+ 3 / 5) (+ 4 / 5) refl
pyth (suc zero)             = dir (Data.Integer.- (+ 5) / 13) (+ 12 / 13) refl
pyth (suc (suc zero))       = dir (+ 8 / 17) (Data.Integer.- (+ 15) / 17) refl
pyth (suc (suc (suc i)))    = pyth i

record Case : Set where
  constructor case
  field
    kernel : Kernel
    st     : Store (na kernel) (ns kernel)
open Case

-- The spectrum of the reduce kernels and of whitecapping.
spec : OceanWaves.Sources.Spectrum
spec = record { n = lanes ; σ = wave 3 2 ; k = wave 5 1 ; w = wave 2 7 ; N = wave 7 3 }

dsParams : OceanWaves.Sources.DsParams
dsParams = record
  { cDs = + 9 / 2 ; delta = + 1 / 2 ; alphaPM = + 457 / 100000
  ; cDs-nonneg = from-yes (0ℚ ≤? + 9 / 2) ; delta-nonneg = from-yes (0ℚ ≤? + 1 / 2)
  ; delta-le-one = from-yes (+ 1 / 2 ≤? 1ℚ) }

windParams : OceanWaves.Sources.WindParams
windParams = record
  { cIn = + 1 / 4 ; rhoRatio = + 3 / 2500 ; ustar = + 3 / 10
  ; cIn-nonneg = from-yes (0ℚ ≤? + 1 / 4) ; rho-nonneg = from-yes (0ℚ ≤? + 3 / 2500) }

cases : List Case
cases =
  case advectK (store ((λ i → + ((3 * i ℕ.+ 1) % 9) / 10) ∷ wave 7 3 ∷ []) (+ 1 / 2 ∷ [])) ∷
  case advectCgK (store (wave 5 2 ∷ wave 3 1 ∷ []) (+ 1 / 4 ∷ + 1 / 2 ∷ lit 2 ∷ [])) ∷
  case sigma2K (store (ramp 7 ∷ []) (+ 981 / 100 ∷ lit 2 ∷ [])) ∷
  case groupSpeedK (store (wave 2 5 ∷ ramp 9 ∷ []) (lit 3 ∷ [])) ∷
  case windK (windStore windParams (wave 3 2) (wave 5 1) (signed 7 0)) ∷
  case etotK (spectrumStore3 spec) ∷
  case dsigK (spectrumStore3 spec) ∷
  case dkK (spectrumStore4 spec) ∷
  case dsK (dsStore dsParams spec) ∷
  case linStepK (store (wave 3 1 ∷ wave 4 2 ∷ wave 7 3 ∷ []) (lit 2 ∷ [])) ∷
  case eulerK (store (wave 3 1 ∷ wave 4 2 ∷ wave 7 3 ∷ []) (+ 1 / 4 ∷ [])) ∷
  case sourceK (sourceStore 1ℚ (+ 1 / 8) (wave 3 1) (wave 4 2) lanes (signed 5 2) (wave 7 3)) ∷
  case snlK (sized lanes (signed 5 2 ∷ []) []) ∷
  case sourceSnlK (sized lanes (wave 3 1 ∷ wave 4 2 ∷ wave 7 3 ∷ signed 5 2 ∷ []) (1ℚ ∷ + 1 / 8 ∷ [])) ∷
  case sxxK (stressStore (wave 3 2) (half 4 1) pyth) ∷
  case sxyK (stressStore (wave 3 2) (half 4 1) pyth) ∷
  case syyK (stressStore (wave 3 2) (half 4 1) pyth) ∷
  []

quoted : String → String
quoted s = "\"" ++ s ++ "\""

values : List ℚ → String
values qs = "[" ++ intersperse ", " (L.map (λ q → quoted (showℚ q)) qs) ++ "]"

-- The exact output of a case: n values for a map kernel, one for a reduce kernel.
expected : Case → List ℚ
expected (case K st) with shape K
... | map    = sample lanes (runMap K st)
... | reduce = runReduce K lanes st ∷ []

-- Each array is given on n + 1 lanes, since a face array has one more value than the cells.
json : Case → String
json c@(case K st) =
  "  " ++ quoted (name K) ++ ": {\n" ++
  "    \"n\": " ++ showℕ lanes ++ ",\n" ++
  "    \"arrays\": {" ++ intersperse ", "
     (toList (zipWith (λ a f → quoted a ++ ": " ++ values (sample (suc lanes) f)) (arrays K) (Store.arr st)))
     ++ "},\n" ++
  "    \"scalars\": {" ++ intersperse ", "
     (toList (zipWith (λ s q → quoted s ++ ": " ++ quoted (showℚ q)) (scalars K) (Store.sc st)))
     ++ "},\n" ++
  "    \"expected\": " ++ values (expected c) ++ "\n  }"

-- The loop kernel: 20 bisection steps; σ spans 1/8 to 7/4 rad/s, in 2 m of water.
iters : ℕ
iters = 20

loopJson : String
loopJson =
  "  \"wavenumber\": {\n" ++
  "    \"n\": " ++ showℕ lanes ++ ",\n" ++
  "    \"iters\": " ++ showℕ iters ++ ",\n" ++
  "    \"arrays\": {\"sigma\": " ++ values (sample (suc lanes) σw) ++ "},\n" ++
  "    \"scalars\": {\"g\": " ++ quoted (showℚ gw) ++ ", \"h\": " ++ quoted (showℚ (lit 2)) ++ "},\n" ++
  "    \"expected\": " ++ values (sample lanes (runLoop wavenumberK iters (store (σw ∷ []) (gw ∷ lit 2 ∷ [])))) ++ "\n  }"
  where
  σw = wave 3 2
  gw = + 981 / 100

-- The whole file: a JSON object from kernel name to its case.
vectors : String
vectors = "{\n" ++ intersperse ",\n" (L.map json cases L.++ (loopJson ∷ [])) ++ "\n}\n"
