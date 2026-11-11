{-# OPTIONS --safe --without-K #-}

-- The size rules of a triangle grid (`triangle-grids/`, `just grids`), in Agda: the size rule,
-- the Courant number of a 600 s step, gradation and WAVEWATCH III's ITER.
module Grids where

import Grids.SizeRule
import Grids.Courant
import Grids.Iter
