{-# OPTIONS --safe --without-K #-}

-- The prose checks in Agda: the ASD-STE100 rules (Simplified Technical English) and the PTC
-- rules that a program decides on the characters of a text, the verdict and report of a run,
-- and the comparison of the facts of two editions. `tools/prose-check/` compiles `Prose.Cli` with
-- a small program that reads the files, so the checks run on the repository's text.
module Prose where

import Prose.Text
import Prose.Words
import Prose.Report
import Prose.Ste
import Prose.Ptc
import Prose.Facts
import Prose.Examples
import Prose.Cli
