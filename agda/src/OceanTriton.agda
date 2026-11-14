{-# OPTIONS --safe --without-K #-}

-- The ocean-wave kernels of `OceanWaves` as Triton GPU kernels (`ocean-triton/`): a small
-- expression language with an exact meaning, the kernels in it with their soundness theorems,
-- the Triton printer and the exact test values; 2-D kernels and the programs of launches that
-- make the model's time step (milestone M2).
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
