{-# OPTIONS --safe --without-K #-}

-- Ocean-wave theory beyond the Lean original, on the kernels of `OceanWaves`: spectral moments
-- and the significant wave height, shoaling and depth-limited breaking, the deep-water limit,
-- refraction by Snell's law, two-dimensional propagation over many steps, wave action on a
-- current, and the model's time loop over many steps. `WaveTheory/README.md` lists the
-- theorems and says which ones are about exact rationals or a `TanhModel` only.
module WaveTheory where

import WaveTheory.Algebra
import WaveTheory.Moments
import WaveTheory.Shoaling
import WaveTheory.DeepWater
import WaveTheory.Refraction
import WaveTheory.Propagation2D
import WaveTheory.WaveAction
import WaveTheory.TimeLoop
import WaveTheory.Examples
