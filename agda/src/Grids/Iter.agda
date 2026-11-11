{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's ITER, ported from part 4 of `z3-scala/src/main/scala/grids/domain/Grids.scala`
-- (`just grids`). The names follow Z3, with `-` for `_`.
--
-- The explicit N-scheme splits a step into ITER sub-steps (model/src/w3profsmd.F90:648-656 at
-- metocean/WW3 92e2cf66). For a positive CFL number cfl with floor fl and fractional part
-- rest = cfl - fl, ITER is NINT(cfl) (half away from zero), plus one when THR8 < rest < 1/2.
-- ITER covers the CFL number up to THR8 = TINY(1d0) (:561). It is 0, so the scheme does not move
-- the spectrum at all, when the CFL number is at most THR8.
--
-- Z3 takes the floor as an integer. With cfl > 0 and fl ≤ cfl < fl + 1 the floor is at least 0,
-- so here it is a natural number m, and fl = ofℕ m. Z3's two counterexamples are witnesses.
module Grids.Iter where

open import Data.Integer using (+_)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _-_; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <⇒≤; ≮⇒≥; <-asym; _<?_; _≤?_; ≤-reflexive; +-monoʳ-≤)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; con)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; subst)
open import Relation.Nullary using (Dec; yes; no; ¬_; contradiction)
open import Relation.Nullary.Decidable using (from-yes; _×-dec_)

open import ContextualBandit.Interface using (ofℕ; ofℕ-nonNeg)
open import OceanWaves.Order using (by-diff; ≤⇒0≤-; +-nonneg)
open import Data.Rational.Properties using (nonNegative⁻¹)

half : ℚ
half = + 1 / 2

-- NINT of a positive number with floor fl: fl when rest < 1/2, else fl + 1.
nintD : (fl rest : ℚ) → Dec (rest < half) → ℚ
nintD fl rest (yes _) = fl
nintD fl rest (no _)  = fl + 1ℚ

-- w3profsmd.F90:648-656: ITER = n, plus one when THR8 < rest < 1/2.
iterD : (n rest thr8 : ℚ) → Dec (rest < thr8) → Dec (thr8 < rest × rest < half) → ℚ
iterD n rest thr8 (yes _) _       = n
iterD n rest thr8 (no _)  (yes _) = n + 1ℚ
iterD n rest thr8 (no _)  (no _)  = n

iter : (fl cfl thr8 : ℚ) → ℚ
iter fl cfl thr8 =
  iterD (nintD fl (cfl - fl) ((cfl - fl) <? half)) (cfl - fl) thr8 ((cfl - fl) <? thr8)
        ((thr8 <? (cfl - fl)) ×-dec ((cfl - fl) <? half))

-- Z3's premises: a positive CFL number, 0 < THR8 < 1/2, and fl the floor of cfl.
WW3 : (fl cfl thr8 : ℚ) → Set
WW3 fl cfl thr8 = 0ℚ < cfl × 0ℚ < thr8 × thr8 < half × fl ≤ cfl × cfl < fl + 1ℚ

-- ---------------------------------------------------------------------------------------------
-- The arithmetic the cases use

private
  minus-le : ∀ cfl t → 0ℚ ≤ t → cfl - t ≤ cfl
  minus-le cfl t 0≤t = by-diff t (solve 2 (λ c t → c :- (c :- t) := t) refl cfl t) 0≤t

  rest-le : ∀ cfl fl t → cfl - fl ≤ t → cfl - t ≤ fl
  rest-le cfl fl t h =
    by-diff (t - (cfl - fl)) (solve 3 (λ c f t → f :- (c :- t) := t :- (c :- f)) refl cfl fl t)
      (≤⇒0≤- h)

  rest-zero : ∀ cfl fl → cfl - fl ≡ 0ℚ → cfl ≤ fl
  rest-zero cfl fl h = by-diff 0ℚ (trans (solve 2 (λ c f → f :- c := con 0ℚ :- (c :- f)) refl cfl fl)
                                         (cong (0ℚ -_) h)) ≤-refl

  le-succ : ∀ x → x ≤ x + 1ℚ
  le-succ x = by-diff 1ℚ (solve 1 (λ x → x :+ con 1ℚ :- x := con 1ℚ) refl x) (from-yes (0ℚ ≤? 1ℚ))

  ofℕ-suc-ge-1 : ∀ k → 1ℚ ≤ ofℕ (suc k)
  ofℕ-suc-ge-1 k = by-diff (ofℕ k) (solve 1 (λ x → con 1ℚ :+ x :- con 1ℚ := x) refl (ofℕ k))
                     (nonNegative⁻¹ (ofℕ k) {{ofℕ-nonNeg k}})

-- ---------------------------------------------------------------------------------------------
-- The statements, first for every answer of the three decisions, then for `iter`

module _ {fl cfl thr8 : ℚ} (ww3 : WW3 fl cfl thr8) where
  private
    rest = cfl - fl
    0≤t : 0ℚ ≤ thr8
    0≤t = <⇒≤ (proj₁ (proj₂ ww3))
    below : cfl < fl + 1ℚ
    below = proj₂ (proj₂ (proj₂ (proj₂ ww3)))
    cover₁ : cfl - thr8 ≤ fl + 1ℚ
    cover₁ = ≤-trans (minus-le cfl thr8 0≤t) (<⇒≤ below)

  iterD-covers-cfl-to-thr8 : ∀ d₁ d₂ d₃ → cfl - thr8 ≤ iterD (nintD fl rest d₁) rest thr8 d₂ d₃
  iterD-covers-cfl-to-thr8 (yes _)   (yes r<t) _ = rest-le cfl fl thr8 (<⇒≤ r<t)
  iterD-covers-cfl-to-thr8 (yes _)   (no _) (yes _) = cover₁
  iterD-covers-cfl-to-thr8 (yes r<½) (no _) (no ¬both) =
    rest-le cfl fl thr8 (≮⇒≥ (λ t<r → ¬both (t<r , r<½)))
  iterD-covers-cfl-to-thr8 (no _)    (yes _) _      = cover₁
  iterD-covers-cfl-to-thr8 (no ¬r<½) (no _) (yes (_ , r<½)) = contradiction r<½ ¬r<½
  iterD-covers-cfl-to-thr8 (no _)    (no _) (no _)  = cover₁

  iterD-covers-cfl-unless-small : rest ≡ 0ℚ ⊎ thr8 < rest →
    ∀ d₁ d₂ d₃ → cfl ≤ iterD (nintD fl rest d₁) rest thr8 d₂ d₃
  iterD-covers-cfl-unless-small (inj₁ r≡0) (yes _) (yes _)   _ = rest-zero cfl fl r≡0
  iterD-covers-cfl-unless-small (inj₂ t<r) (yes _) (yes r<t) _ = contradiction t<r (<-asym r<t)
  iterD-covers-cfl-unless-small _ (yes _) (no _) (yes _)     = <⇒≤ below
  iterD-covers-cfl-unless-small (inj₁ r≡0) (yes _) (no _) (no _) = rest-zero cfl fl r≡0
  iterD-covers-cfl-unless-small (inj₂ t<r) (yes r<½) (no _) (no ¬both) = contradiction (t<r , r<½) ¬both
  iterD-covers-cfl-unless-small _ (no _) (yes _) _           = <⇒≤ below
  iterD-covers-cfl-unless-small _ (no ¬r<½) (no _) (yes (_ , r<½)) = contradiction r<½ ¬r<½
  iterD-covers-cfl-unless-small _ (no _) (no _) (no _)       = <⇒≤ below

  iterD-ge-floor : ∀ d₁ d₂ d₃ → fl ≤ iterD (nintD fl rest d₁) rest thr8 d₂ d₃
  iterD-ge-floor (yes _) (yes _) _       = ≤-refl
  iterD-ge-floor (yes _) (no _)  (yes _) = le-succ fl
  iterD-ge-floor (yes _) (no _)  (no _)  = ≤-refl
  iterD-ge-floor (no _)  (yes _) _       = le-succ fl
  iterD-ge-floor (no _)  (no _)  (yes _) = ≤-trans (le-succ fl) (le-succ (fl + 1ℚ))
  iterD-ge-floor (no _)  (no _)  (no _)  = le-succ fl

-- iter_covers_cfl_to_thr8 (w3profsmd.F90:649).
iter-covers-cfl-to-thr8 : ∀ fl cfl thr8 → WW3 fl cfl thr8 → cfl - thr8 ≤ iter fl cfl thr8
iter-covers-cfl-to-thr8 fl cfl thr8 ww3 = iterD-covers-cfl-to-thr8 ww3 (cfl - fl <? half) (cfl - fl <? thr8) ((thr8 <? cfl - fl) ×-dec (cfl - fl <? half))

-- iter_covers_cfl_unless_rest_in_(0,thr8].
iter-covers-cfl-unless-rest-in-0-thr8 : ∀ fl cfl thr8 → WW3 fl cfl thr8 →
  cfl - fl ≡ 0ℚ ⊎ thr8 < cfl - fl → cfl ≤ iter fl cfl thr8
iter-covers-cfl-unless-rest-in-0-thr8 fl cfl thr8 ww3 h = iterD-covers-cfl-unless-small ww3 h (cfl - fl <? half) (cfl - fl <? thr8) ((thr8 <? cfl - fl) ×-dec (cfl - fl <? half))

-- iter_at_least_1_above_thr8, with the floor a natural number m.
iter-at-least-1-above-thr8 : ∀ m cfl thr8 → WW3 (ofℕ m) cfl thr8 → thr8 < cfl →
  1ℚ ≤ iter (ofℕ m) cfl thr8
iter-at-least-1-above-thr8 (suc k) cfl thr8 ww3 _ =
  ≤-trans (ofℕ-suc-ge-1 k) (iterD-ge-floor ww3 (cfl - ofℕ (suc k) <? half) (cfl - ofℕ (suc k) <? thr8) ((thr8 <? cfl - ofℕ (suc k)) ×-dec (cfl - ofℕ (suc k) <? half)))
iter-at-least-1-above-thr8 zero cfl thr8 ww3 t<c = go (cfl - 0ℚ <? half) (cfl - 0ℚ <? thr8) ((thr8 <? cfl - 0ℚ) ×-dec (cfl - 0ℚ <? half))
  where
  t<r : thr8 < cfl - 0ℚ
  t<r = subst (thr8 <_) (sym (solve 1 (λ c → c :- con 0ℚ := c) refl cfl)) t<c
  one : 1ℚ ≤ 0ℚ + 1ℚ
  one = from-yes (1ℚ ≤? 0ℚ + 1ℚ)
  go : ∀ d₁ d₂ d₃ → 1ℚ ≤ iterD (nintD 0ℚ (cfl - 0ℚ) d₁) (cfl - 0ℚ) thr8 d₂ d₃
  go (yes _)   (yes r<t) _          = contradiction t<r (<-asym r<t)
  go (yes _)   (no _)    (yes _)    = from-yes (1ℚ ≤? 0ℚ + 1ℚ)
  go (yes r<½) (no _)    (no ¬both) = contradiction (t<r , r<½) ¬both
  go (no _)    (yes _)   _          = one
  go (no _)    (no _)    (yes _)    = from-yes (1ℚ ≤? 0ℚ + 1ℚ + 1ℚ)
  go (no _)    (no _)    (no _)     = one

-- Z3's counterexamples, as a witness: THR8 = 1/4 and cfl = 1/8, so fl = 0 and rest = 1/8 is in
-- (0, THR8]. It rounds down: ITER = 0. That breaks iter_covers_cfl and
-- iter_at_least_1 (w3profsmd.F90:663): no sub-step runs.
small-cfl : WW3 0ℚ (+ 1 / 8) (+ 1 / 4) × iter 0ℚ (+ 1 / 8) (+ 1 / 4) ≡ 0ℚ
small-cfl = (from-yes (0ℚ <? + 1 / 8) , from-yes (0ℚ <? + 1 / 4) , from-yes (+ 1 / 4 <? half) ,
             from-yes (0ℚ ≤? + 1 / 8) , from-yes (+ 1 / 8 <? 0ℚ + 1ℚ)) , refl

iter-covers-cfl-refuted : iter 0ℚ (+ 1 / 8) (+ 1 / 4) < + 1 / 8
iter-covers-cfl-refuted = from-yes (iter 0ℚ (+ 1 / 8) (+ 1 / 4) <? + 1 / 8)

iter-at-least-1-refuted : iter 0ℚ (+ 1 / 8) (+ 1 / 4) < 1ℚ
iter-at-least-1-refuted = from-yes (iter 0ℚ (+ 1 / 8) (+ 1 / 4) <? 1ℚ)
