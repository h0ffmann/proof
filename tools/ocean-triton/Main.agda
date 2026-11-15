{-# OPTIONS --without-K --guardedness #-}

-- The program of the Triton emitter: it writes the Python module that `OceanTriton.Emit`
-- prints, the exact values of `OceanTriton.Vectors`, the 2-D module of `OceanTriton.EmitGrid`,
-- the values of `OceanTriton.GridVectors`, the gather module of `OceanTriton.EmitGather` and the
-- values of `OceanTriton.GatherVectors`, and W3SDB1's module and values from
-- `OceanTriton.W3SDB1`, and the lane programs of `OceanTriton.EmitLanes` with their values, to
-- the ten paths it is given. This file does
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
open import OceanTriton.Shallow using (m3Kernels; fusedKernels; strang)
open import OceanTriton.W3SBT1 using (sbtKernels)
open import OceanTriton.Mesh using (meshK; meshProgram)
open import OceanTriton.W3SNL1 using (ueK; sK; dK; snl1; module SA)
open import OceanTriton.EmitGather using (gatherModule)
open import OceanTriton.Gather using (KernelG)
open import OceanTriton.GatherVectors using (gatherVectors; meshTriangles)
open import OceanTriton.Freq using (freqKernels)
open import OceanTriton.W3SDB1 using (sdbModule; sdbVectors)
open import OceanTriton.EmitLanes using (lanesModule; prog)
open import OceanTriton.LanesVectors using (lanesJson)
open import OceanTriton.W3SDS4 using (sds4Sig; sds4)
open import OceanTriton.W3SDS4Vectors using (sds4Cases)
open import OceanTriton.W3SIN4 using (sin4Sig; sin4)
open import OceanTriton.W3SIN4Vectors using (sin4Cases)
open import OceanTriton.W3SPR4 using (spr4Sig; spr4)
open import OceanTriton.W3SPR4Vectors using (spr4Cases)
open import OceanTriton.W3SLN1 using (sln1Sig; sln1)
open import OceanTriton.W3SLN1Vectors using (sln1Cases)
open import OceanTriton.W3SRCE using (stepSig; srceStep; tailSig; srceTail)
open import OceanTriton.W3SRCEVectors using (srceStepCases; srceTailCases)
open import OceanTriton.W3SRCEFlux using (passSig; srcePass; endSig; srceEnd)
open import OceanTriton.W3SRCEFluxVectors using (srcePassCases; srceEndCases)
open import OceanTriton.WAVNU1 using (wavnuSig; wavnu1)
open import OceanTriton.WAVNU1Vectors using (wavnu1Cases)
open import OceanTriton.TABUSTRESS using (tautSig; taut)
open import OceanTriton.TABUSTRESSVectors using (tautCases)
open import OceanTriton.TABUTAUHF using (tauhfSig; tauhf)
open import OceanTriton.TABUTAUHFVectors using (tauhfCases)
open import OceanTriton.TABUTAUHF2 using (tauhf2Sig; tauhf2)
open import OceanTriton.TABUTAUHF2Vectors using (tauhf2Cases)
open import OceanTriton.INSIN4 using (insin4Sig; insin4)
open import OceanTriton.INSIN4Vectors using (insin4Cases)

-- The gather kernels: the fused ones, W3SBT1's, the advection in frequency, the mesh step (rows of 3), and W3SNL1's
-- eleven, with up to 16 tail rows: the R of `ue`, which REP_BOUNDS checks. WW3's grids have fewer
-- (ww3_ts1: NFRHGH - NFR = 7), and the vectors use 2.
gather : List KernelG
gather = fusedKernels ++ sbtKernels ++ freqKernels ++ meshK 2 2 ∷ ueK 16 ∷ SA.sa1K ∷ SA.sa2K ∷ SA.da1cK ∷ SA.da1pK ∷ SA.da1mK
         ∷ SA.da2cK ∷ SA.da2pK ∷ SA.da2mK ∷ sK ∷ dK ∷ []

main : Main
main = run $ getArgs >>= λ where
  (py ∷ json ∷ gpy ∷ gjson ∷ hpy ∷ hjson ∷ spy ∷ sjson ∷ lpy ∷ ljson ∷ []) →
    writeFile py (module′ (toList kernels ++ stepKernels ++ m3Kernels) loopKernels) >> writeFile json vectors >>
    writeFile gpy (gridModule kernels2 (programs ++ strang ∷ [])) >> writeFile gjson gridVectors >>
    writeFile hpy (gatherModule gather (meshProgram 2 2 ∷ meshTriangles ∷ snl1 16 ∷ [])) >> writeFile hjson gatherVectors >>
    writeFile spy sdbModule >> writeFile sjson sdbVectors >>
    writeFile lpy (lanesModule (prog sds4Sig sds4 ∷ prog sin4Sig sin4 ∷ prog spr4Sig spr4 ∷ prog sln1Sig sln1
                                ∷ prog stepSig srceStep ∷ prog tailSig srceTail ∷ prog passSig srcePass
                                ∷ prog endSig srceEnd ∷ prog wavnuSig wavnu1 ∷ prog tautSig taut
                                ∷ prog tauhfSig tauhf ∷ prog tauhf2Sig tauhf2 ∷ prog insin4Sig insin4 ∷ [])) >>
    writeFile ljson (lanesJson (sds4Cases ∷ sin4Cases ∷ spr4Cases ∷ sln1Cases ∷ srceStepCases ∷ srceTailCases
                                ∷ srcePassCases ∷ srceEndCases ∷ wavnu1Cases ∷ tautCases ∷ tauhfCases ∷ tauhf2Cases ∷ insin4Cases ∷ []))
  _ → putStrLn "usage: Main KERNELS.py VECTORS.json GRID.py GRID_VECTORS.json GATHER.py GATHER_VECTORS.json SDB.py SDB_VECTORS.json LANES.py LANES_VECTORS.json"
      >> exitWith (ExitFailure (+ 2))
