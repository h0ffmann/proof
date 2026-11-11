{-# OPTIONS --safe --without-K #-}

-- The port audit of chaceon (`port-audit/README.md`) in Agda: all 28 statements of
-- `tools/port-audit/Chaceon.hs`. The division rewrite over ℕ and ℚ, the time step of W3SRCE over
-- ℚ, and, over a bit-level model of IEEE 754 binary32, Fortran's intrinsics and the f32 part of
-- the time step. The coverage table is checked data.
module PortAudit where

import PortAudit.Division
import PortAudit.Rounding
import PortAudit.TimeStep
import PortAudit.Float32
import PortAudit.Float32Exact
import PortAudit.Float32Examples
import PortAudit.Intrinsics
import PortAudit.StepF32
import PortAudit.Coverage
