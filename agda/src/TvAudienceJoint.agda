{-# OPTIONS --safe --without-K #-}

-- Joint estimation of the channels of a slot against estimation of each channel alone: when the
-- joint step is better, by how much, and when it is not. `tv-audience/joint.md` says what is
-- proved and under which assumptions.
module TvAudienceJoint where

import TvAudience.Joint
import TvAudience.JointExamples
