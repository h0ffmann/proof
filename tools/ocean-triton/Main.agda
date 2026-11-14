{-# OPTIONS --without-K --guardedness #-}

-- The program of the Triton emitter: it writes the Python module that `OceanTriton.Emit`
-- prints, the exact values of `OceanTriton.Vectors`, the 2-D module of `OceanTriton.EmitGrid`
-- and the values of `OceanTriton.GridVectors`, to the four paths it is given. This file does
-- output only, so it cannot be --safe (the standard library's IO is not); the kernels,
-- their soundness theorems, the printer and the values are in agda/src/OceanTriton/, which is
-- --safe.
module Main where

open import Data.List using (List; []; _∷_)
open import Data.Vec using (toList)
open import Data.Integer using (+_)
open import Function using (_$_)
open import IO
open import System.Environment using (getArgs)
open import System.Exit using (exitWith; ExitFailure)

open import Data.List using (_++_)
open import OceanTriton.Kernels using (kernels)
open import OceanTriton.Step using (stepKernels; loopKernels)
open import OceanTriton.Emit using (module′)
open import OceanTriton.Vectors using (vectors)
open import OceanTriton.Space using (kernels2; programs)
open import OceanTriton.EmitGrid using (gridModule)
open import OceanTriton.GridVectors using (gridVectors)

main : Main
main = run $ getArgs >>= λ where
  (py ∷ json ∷ gpy ∷ gjson ∷ []) →
    writeFile py (module′ (toList kernels ++ stepKernels) loopKernels) >> writeFile json vectors >>
    writeFile gpy (gridModule kernels2 programs) >> writeFile gjson gridVectors
  _ → putStrLn "usage: Main KERNELS.py VECTORS.json GRID.py GRID_VECTORS.json" >> exitWith (ExitFailure (+ 2))
