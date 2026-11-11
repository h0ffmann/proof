{-# OPTIONS --safe --without-K #-}

-- The ocean-wave kernels (`ocean-waves/`) in Agda: dispersion, bisection, upwind advection,
-- source terms and one model step, with their examples.
module OceanWaves where

import OceanWaves.Order
import OceanWaves.Sums
import OceanWaves.Dispersion
import OceanWaves.Bisection
import OceanWaves.Advection
import OceanWaves.Sources
import OceanWaves.ActionBalance
import OceanWaves.Examples
import OceanWaves.ModelExamples
