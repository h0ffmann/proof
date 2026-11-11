{-# OPTIONS --safe --without-K #-}

-- The fat-tail diagnostics of `fat-tails/` over exact rationals and finite samples: the sample
-- lemmas, the MAD and the kurtosis, the MS plot's max-to-sum ratio, κ's ratio of MADs, the Hill
-- estimator on logarithms, the expected-shortfall factor, the EWMA variance, and their examples.
-- `fat-tails/agda.md` says what is proved and what stays in the Python.
module FatTails where

import FatTails.Sample
import FatTails.Moments
import FatTails.MaxSum
import FatTails.Kappa
import FatTails.Tail
import FatTails.Ewma
import FatTails.Examples
