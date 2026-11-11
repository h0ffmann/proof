{-# OPTIONS --safe --without-K #-}

-- The coverage table of the port audit of chaceon (`port-audit/README.md`, between the
-- coverage markers), as checked data. The counts come from `tools/port-audit/Coverage.hs`, which
-- reads chaceon's `rust/ports.tsv` and `switches/` and WW3's `model/src/*.F90` and CMake rules at
-- their pins. Agda type-checks under --safe and cannot read a file, so it cannot make these
-- counts. It checks what holds between them: each sum, each difference and each rounded share
-- that the table prints, by computation (`refl`). A typo in one cell of the table breaks one of
-- these equalities.
--
-- It also proves the finding about WW3's rules for every switch set: when `requires` asks for
-- ST3 and ST4 both on and the source-term category allows exactly one ST option, no accepted
-- switch set turns STAB3 on (`stab3-never`).
module PortAudit.Coverage where

open import Data.Bool using (Bool; true; false)
open import Data.Empty using (⊥)
open import Data.List using (List; []; _∷_)
open import Data.Product using (_×_; _,_)
open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _∸_; _/_)
open import Data.Nat.Properties using (suc-injective)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

-- ---------------------------------------------------------------------------------------------
-- The table, chaceon fe531e1e and WW3 92e2cf66; the unit is a Fortran code line

all-lines translated compiled integrated capture-only no-switch dead : ℕ
all-lines    = 120705
translated   = 45104
compiled     = 72642    -- by switch_chaceon_shrd, the target build
integrated   = 34304    -- translated and compiled by the target build
capture-only = 2993     -- translated, compiled only by a capture switch file
no-switch    = 7807     -- translated, compiled by no chaceon switch file
dead         = 4330     -- compiled by no switch set that WW3's rules accept

-- Evidence in rust/ports.tsv: translated, integrated, in some chaceon switch file.
record Evidence : Set where
  constructor row
  field
    tr in-target in-some : ℕ

spirv host routine translated-only : Evidence
spirv           = row 3391 2180 2355
host            = row 26135 20683 21642
routine         = row 2334 561 1966
translated-only = row 13244 10880 11334

-- The share in percent, rounded to the nearest integer.
pct : ℕ → ℕ → ℕ
pct a zero    = 0
pct a (suc b) = (200 * a + suc b) / (2 * suc b)

-- ---------------------------------------------------------------------------------------------
-- What holds between the cells

open Evidence

evidence-sums-to-translated : tr spirv + tr host + tr routine + tr translated-only ≡ translated
evidence-sums-to-translated = refl

evidence-sums-to-integrated :
  in-target spirv + in-target host + in-target routine + in-target translated-only ≡ integrated
evidence-sums-to-integrated = refl

-- A translated line is in the target, or only in a capture switch file, or in none.
translated-splits :
  in-some spirv + in-some host + in-some routine + in-some translated-only ≡ integrated + capture-only
translated-splits = refl

no-switch≡ : translated ∸ (integrated + capture-only) ≡ no-switch
no-switch≡ = refl

share-translated : pct translated all-lines ≡ 37
share-translated = refl

share-compiled : pct compiled all-lines ≡ 60
share-compiled = refl

share-integrated : pct integrated compiled ≡ 47
share-integrated = refl

share-capture-only : pct capture-only translated ≡ 7
share-capture-only = refl

share-no-switch : pct no-switch translated ≡ 17
share-no-switch = refl

share-dead : pct dead all-lines ≡ 4
share-dead = refl

-- Each switch file: the translated lines among those it compiles, as a share.
switch-shares :
  pct 34571 72959 ≡ 47 × pct 34390 72743 ≡ 47 × pct 34304 72642 ≡ 47 × pct 32993 71212 ≡ 46 ×
  pct 33311 71576 ≡ 47 × pct 33339 71610 ≡ 47 × pct 33385 71654 ≡ 47 × pct 33404 71684 ≡ 47 ×
  pct 34994 77231 ≡ 45
switch-shares = refl , refl , refl , refl , refl , refl , refl , refl , refl

-- The target build's row of the switch table is the integrated line count.
target-row : 34304 ≡ integrated
target-row = refl

-- ---------------------------------------------------------------------------------------------
-- STAB3 can never be built

count : List Bool → ℕ
count []           = 0
count (true  ∷ bs) = suc (count bs)
count (false ∷ bs) = count bs

-- The source-term category is "one": exactly one of its options is on. ST3 and ST4 are two of
-- them; `others` are the rest, in any order. check_switches.cmake reads each string of
-- STAB3's `requires` as a switch that must be on.
stab3-never : ∀ (st3 st4 stab3 : Bool) (others : List Bool) →
              count (st3 ∷ st4 ∷ others) ≡ 1 →
              (stab3 ≡ true → st3 ≡ true) → (stab3 ≡ true → st4 ≡ true) →
              stab3 ≡ true → ⊥
stab3-never st3 st4 stab3 others one req3 req4 on with req3 on | req4 on
stab3-never true true stab3 others one req3 req4 on | refl | refl = two (suc-injective one)
  where
    two : suc (count others) ≡ 0 → ⊥
    two ()
