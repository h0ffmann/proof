{-# OPTIONS --safe --without-K #-}

-- The TV audience forecasting of `tv-audience/` over exact rationals and finite lists: WAPE and
-- the errors it relates to, the seasonal naive and four-week baselines, the train/test split,
-- the panel's rating, share and PUT, the JCS share layer and its theory, the slot winner and
-- its accuracy, a tree ensemble's prediction, the rival line-up features, the neurosymbolic
-- utility, and the JCS and neurosymbolic JCS pipelines end to end, with their examples.
-- `tv-audience/agda.md` says what is proved and what stays in the Python.
module TvAudience where

import TvAudience.Wape
import TvAudience.Baselines
import TvAudience.Split
import TvAudience.Panel
import TvAudience.Jcs
import TvAudience.Winner
import TvAudience.Trees
import TvAudience.JcsTheory
import TvAudience.Features
import TvAudience.Neural
import TvAudience.Pipeline
import TvAudience.Examples
