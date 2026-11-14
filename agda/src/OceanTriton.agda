{-# OPTIONS --safe --without-K #-}

-- The ocean-wave kernels of `OceanWaves` as Triton GPU kernels (`ocean-triton/`): a small
-- expression language with an exact meaning, the kernels in it with their soundness theorems,
-- the Triton printer and the exact test values; 2-D kernels and the programs of launches that
-- make the model's time step (milestone M2); kernels that read through index arrays, fused
-- reductions, refraction, shoaling, Strang splitting, an unstructured mesh, and WAVEWATCH III's
-- W3SBT1, W3SNL1 and W3SDB1 transcribed from the Fortran at a pinned commit, and advection in
-- frequency (milestones M3 and M4).
module OceanTriton where

import OceanTriton.Expr
import OceanTriton.Kernels
import OceanTriton.Step
import OceanTriton.Emit
import OceanTriton.Vectors
import OceanTriton.Grid
import OceanTriton.Space
import OceanTriton.EmitGrid
import OceanTriton.GridVectors
import OceanTriton.Gather
import OceanTriton.Shallow
import OceanTriton.Mesh
import OceanTriton.W3SBT1
import OceanTriton.W3SNL1
import OceanTriton.EmitGather
import OceanTriton.GatherVectors
import OceanTriton.Freq
import OceanTriton.W3SDB1
