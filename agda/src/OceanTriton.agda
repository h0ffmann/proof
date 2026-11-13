{-# OPTIONS --safe --without-K #-}

-- The ocean-wave kernels of `OceanWaves` as Triton GPU kernels (`ocean-triton/`): a small
-- expression language with an exact meaning, the kernels in it with their soundness theorems,
-- the Triton printer and the exact test values.
module OceanTriton where

import OceanTriton.Expr
import OceanTriton.Kernels
import OceanTriton.Emit
import OceanTriton.Vectors
