{-# OPTIONS --safe --without-K #-}

-- Exact test values for the gather kernels and programs of milestones M3 and M4. Each value is
-- the specification's, not the kernel's: `sbtS`, `sbtD` (by `sbtS-sound`, `sbtD-sound`),
-- `meshRun` (by `mesh-run`), and W3SNL1's `snlS`, `snlD` (by `snl1-S`, `snl1-D`). The two fused
-- kernels give their kernel's meaning, which is `breakScale` and `dsRate` by refl.
-- `ocean-triton/check_gather.py` runs the printed Triton on the same inputs and compares.
--
-- The inputs reach both branches of every choice: W3SBT1 has bins on both sides of k d = 6 and
-- of c_g k / σ = 1/2; the mesh rows are padded (degree 2 in rows of 3); W3SNL1's UE has the zero
-- rows, the real rows and two tail rows (FACHFE once and twice). Its index tables are synthetic
-- and in range: the theorems hold for every table, and INSNL1's are data (W3SNL1.agda).
module OceanTriton.GatherVectors where

open import Data.Fin using (toℕ)
open import Data.Integer using (+_)
open import Data.List as L using (List; []; _∷_; upTo)
open import Data.Nat as ℕ using (ℕ; _*_; _%_)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_)
open import Data.Rational.Show using () renaming (show to showℚ)
open import Data.String using (String; _++_; intersperse)
open import Data.Vec as V using (Vec; []; _∷_; lookup)

open import WaveTheory.Unstructured using (Edge; edge; meshRun)
open import OceanTriton.Gather using (sg; runG)
open import OceanTriton.Shallow using (breakScaleK; dsFusedK)
open import OceanTriton.W3SBT1 using (Bottom; sbtD; sbtS)
open import OceanTriton.Mesh using (woutT; winT; srcT)
open import OceanTriton.W3SNL1 using (Snl1; module Spec; msk; kofT; cntT; kofST; selfT)
  renaming (srcT to ueSrcT)

private
  quoted : String → String
  quoted s = "\"" ++ s ++ "\""

  qs : List ℚ → String
  qs xs = "[" ++ intersperse ", " (L.map (λ q → quoted (showℚ q)) xs) ++ "]"

  ns : List ℕ → String
  ns xs = "[" ++ intersperse ", " (L.map showℕ xs) ++ "]"

  tab : ∀ {A : Set} → ℕ → (ℕ → A) → List A
  tab n f = L.map f (upTo n)

  named : ∀ {A : Set} → (A → String) → List (String × A) → String
  named sh xs = "{" ++ intersperse ", " (L.map (λ p → quoted (proj₁ p) ++ ": " ++ sh (proj₂ p)) xs) ++ "}"

  -- A positive pattern (a i + b mod 13 + 1) / 8, as in OceanTriton.Vectors.
  wave : ℕ → ℕ → ℕ → ℚ
  wave a b i = + ((a * i ℕ.+ b) % 13 ℕ.+ 1) / 8

  -- A kernel run alone: its arrays, index arrays and scalars in the kernel's order.
  kcase : String → ℕ → List (List ℚ) → List (List ℕ) → List ℚ → List ℚ → String
  kcase name n as is ss out =
    "    " ++ quoted name ++ ": {\"n\": " ++ showℕ n ++ ",\n" ++
    "      \"arrays\": [" ++ intersperse ", " (L.map qs as) ++ "],\n" ++
    "      \"idxs\": [" ++ intersperse ", " (L.map ns is) ++ "],\n" ++
    "      \"scalars\": " ++ qs ss ++ ",\n" ++
    "      \"expected\": " ++ qs out ++ "}"

  -- A program: its input buffers, index arrays, parameters, lane counts, runs, results.
  pcase : String → List (String × List ℚ) → List (String × List ℕ) → List (String × ℚ) →
          List (String × ℕ) → ℕ → List (String × List ℚ) → String
  pcase name bs is ps ls k out =
    "    " ++ quoted name ++ ": {\"runs\": " ++ showℕ k ++ ",\n" ++
    "      \"buffers\": " ++ named qs bs ++ ",\n" ++
    "      \"indices\": " ++ named ns is ++ ",\n" ++
    "      \"params\": " ++ named (λ q → quoted (showℚ q)) ps ++ ",\n" ++
    "      \"sizes\": " ++ named showℕ ls ++ ",\n" ++
    "      \"expected\": " ++ named qs out ++ "}"

-- ---------------------------------------------------------------------------------------------
-- The fused kernels: 20 bins, a cap that binds (γ² h² / 16 below m0)

breakScaleCase : String
breakScaleCase = kcase "break_scale" n (tab n e ∷ []) [] (γ ∷ h ∷ [])
  (tab n (runG breakScaleK n (sg (e ∷ []) [] (γ ∷ h ∷ []))))
  where
  n = 20
  e = wave 5 2
  γ = + 4 / 5
  h = + 3 / 2

dsFusedCase : String
dsFusedCase = kcase "ds_fused" n (tab n σ ∷ tab n N ∷ tab n w ∷ tab n k ∷ []) [] (c ∷ δ ∷ α ∷ [])
  (tab n (runG dsFusedK n (sg (σ ∷ N ∷ w ∷ k ∷ []) [] (c ∷ δ ∷ α ∷ []))))
  where
  n = 20
  σ = λ i → + (i ℕ.+ 2) / 4
  N = wave 7 3
  w = λ i → + ((i % 3) ℕ.+ 1) / 16
  k = λ i → + ((i ℕ.+ 2) * (i ℕ.+ 2)) / 160
  c = + 33 / 10
  δ = + 1 / 2
  α = + 3 / 1000

-- ---------------------------------------------------------------------------------------------
-- W3SBT1: 12 bins of 3 directions in 3/2 m; k d crosses 6 between bins 7 and 8

bottom : Bottom
bottom = record
  { sbtc1 = + 38 / 1000 ; depth = + 3 / 2
  ; wn = λ ik → + (ik ℕ.+ 1) / 2
  ; cg = λ ik → + ((3 * ik ℕ.+ 1) % 5 ℕ.+ 1) / 4
  ; sig = λ ik → + (ik ℕ.+ 2) / 3
  ; mapwn = λ is → is ℕ./ 3
  ; A = wave 7 3 }

private
  sbtIn : List (List ℚ)
  sbtIn = tab 36 (Bottom.A bottom) ∷ tab 12 (Bottom.wn bottom) ∷ tab 12 (Bottom.cg bottom) ∷ tab 12 (Bottom.sig bottom) ∷ []

sbtDCase sbtSCase : String
sbtDCase = kcase "w3sbt1_d" 36 sbtIn (tab 36 (Bottom.mapwn bottom) ∷ []) (Bottom.sbtc1 bottom ∷ Bottom.depth bottom ∷ [])
  (tab 36 (sbtD bottom))
sbtSCase = kcase "w3sbt1_s" 36 sbtIn (tab 36 (Bottom.mapwn bottom) ∷ []) (Bottom.sbtc1 bottom ∷ Bottom.depth bottom ∷ [])
  (tab 36 (sbtS bottom))

-- ---------------------------------------------------------------------------------------------
-- The mesh: 6 nodes, a ring and three chords, rows of 3 (Do′ = Di′ = 2), four steps

meshEdges : List Edge
meshEdges =
  edge 0 1 q ∷ edge 1 2 q ∷ edge 2 3 q ∷ edge 3 4 q ∷ edge 4 5 q ∷ edge 5 0 q ∷
  edge 0 3 e ∷ edge 2 5 e ∷ edge 4 1 e ∷ []
  where q = + 1 / 4 ; e = + 1 / 8

meshCase : String
meshCase = pcase "mesh"
  (("M" , tab 6 M) ∷ ("wout" , tab 18 (woutT 2 meshEdges)) ∷ ("win" , tab 18 (winT 2 meshEdges)) ∷ [])
  (("src" , tab 18 (srcT 2 meshEdges)) ∷ []) [] (("nodes" , 6) ∷ []) 4
  (("M" , tab 6 (meshRun meshEdges 4 M)) ∷ [])
  where M = wave 5 1

-- ---------------------------------------------------------------------------------------------
-- W3SNL1: NTH = 4, NFR = 3, NFRHGH = 5 (two tail rows); 24 positions of UE and SA, 12 points

snlConfig : Snl1
snlConfig = record
  { nth′ = 3 ; nfr′ = 2 ; ntail = 2
  ; A = wave 7 3 ; sig = λ r → + (r ℕ.+ 2) / 2 ; cg = λ r → + 3 / (2 ℕ.+ r) ; af11 = λ p → + (p % 5 ℕ.+ 1) / 4
  ; tpiinv = + 4 / 25 ; fachfe = + 3 / 5 ; cons = + 2 / 1
  ; dal1 = + 3 / 7 ; dal2 = + 5 / 11 ; dal3 = + 2 / 9
  ; awg = + 1 / 4 ∷ + 1 / 8 ∷ + 3 / 8 ∷ + 1 / 4 ∷ + 1 / 5 ∷ + 2 / 5 ∷ + 1 / 10 ∷ + 3 / 10 ∷ []
  ; swg = + 1 / 16 ∷ + 1 / 64 ∷ + 9 / 64 ∷ + 1 / 16 ∷ + 1 / 25 ∷ + 4 / 25 ∷ + 1 / 100 ∷ + 9 / 100 ∷ []
  ; ipim = V.tabulate (λ j → λ p → ((5 * toℕ j ℕ.+ 7) * p ℕ.+ 3 * toℕ j ℕ.+ 1) % 24)
  ; ic = V.tabulate (λ j → λ q → ((7 * toℕ j ℕ.+ 5) * q ℕ.+ 2 * toℕ j ℕ.+ 3) % 24) }

private
  nue nsa nspec : ℕ
  nue = 24
  nsa = 24
  nspec = 12

  ipNames icNames : Vec String 16
  ipNames = "ip11" ∷ "ip12" ∷ "ip13" ∷ "ip14" ∷ "im11" ∷ "im12" ∷ "im13" ∷ "im14" ∷ "ip21" ∷ "ip22" ∷ "ip23" ∷ "ip24" ∷ "im21" ∷ "im22" ∷ "im23" ∷ "im24" ∷ []
  icNames = "ic11" ∷ "ic12" ∷ "ic21" ∷ "ic22" ∷ "ic31" ∷ "ic32" ∷ "ic41" ∷ "ic42" ∷ "ic51" ∷ "ic52" ∷ "ic61" ∷ "ic62" ∷ "ic71" ∷ "ic72" ∷ "ic81" ∷ "ic82" ∷ []

  table : ℕ → Vec String 16 → Vec (ℕ → ℕ) 16 → List (String × List ℕ)
  table n xs fs = V.toList (V.zipWith (λ x f → x , tab n f) xs fs)

  pnames : Vec String 8 → Vec ℚ 8 → List (String × ℚ)
  pnames xs vs = V.toList (V.zipWith _,_ xs vs)

  X = snlConfig
  open Spec X using (snlS; snlD)

snl1Case : String
snl1Case = pcase "w3snl1"
  (("A" , tab nspec (Snl1.A X)) ∷ ("sig" , tab 3 (Snl1.sig X)) ∷ ("cg" , tab 3 (Snl1.cg X))
   ∷ ("msk" , tab nue (msk X)) ∷ ("af11" , tab nsa (Snl1.af11 X)) ∷ [])
  (("src" , tab nue (ueSrcT X)) ∷ ("kof" , tab nue (kofT X)) ∷ ("cnt" , tab nue (cntT X))
   ∷ table nsa ipNames (Snl1.ipim X) L.++ table nspec icNames (Snl1.ic X)
   L.++ (("kofS" , tab nspec (kofST X)) ∷ ("self" , tab nspec (selfT X)) ∷ []))
  (("tpiinv" , Snl1.tpiinv X) ∷ ("fachfe" , Snl1.fachfe X) ∷ ("cons" , Snl1.cons X)
   ∷ ("dal1" , Snl1.dal1 X) ∷ ("dal2" , Snl1.dal2 X) ∷ ("dal3" , Snl1.dal3 X)
   ∷ pnames ("awg1" ∷ "awg2" ∷ "awg3" ∷ "awg4" ∷ "awg5" ∷ "awg6" ∷ "awg7" ∷ "awg8" ∷ []) (Snl1.awg X)
   L.++ pnames ("swg1" ∷ "swg2" ∷ "swg3" ∷ "swg4" ∷ "swg5" ∷ "swg6" ∷ "swg7" ∷ "swg8" ∷ []) (Snl1.swg X))
  (("nue" , nue) ∷ ("nsa" , nsa) ∷ ("nspec" , nspec) ∷ []) 1
  (("S" , tab nspec snlS) ∷ ("D" , tab nspec snlD) ∷ [])

gatherVectors : String
gatherVectors =
  "{\n  \"kernels\": {\n" ++ intersperse ",\n" (breakScaleCase ∷ dsFusedCase ∷ sbtDCase ∷ sbtSCase ∷ []) ++
  "\n  },\n  \"programs\": {\n" ++ intersperse ",\n" (meshCase ∷ snl1Case ∷ []) ++ "\n  }\n}\n"
