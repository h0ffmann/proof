{-# OPTIONS --safe --without-K #-}

-- The decision layer of the text checks of z3-scala (the PTC rules, the PTC-9 noise catalogue
-- and the language rule), in Agda.
module TextChecks where

import TextChecks.Verdict
import TextChecks.Ptc
import TextChecks.NoiseCatalogue
import TextChecks.Language
