{-# OPTIONS --safe --without-K #-}

-- Group S of the port audit of chaceon (`z3-scala/src/main/scala/portaudit/domain/Chaceon.scala`,
-- `just port-audit`), the part over the reals: the time step of W3SRCE in
-- rust/crates/ww3-kernels/src/srce.rs at the commit that `Chaceon.scala` pins. Here over ℚ, with
-- Lean's total division `_/₀_` (`OceanWaves.Order`). The names follow Z3, with `-` for `_`.
--
-- * implicit_le_explicit (srce.rs:617): the semi-implicit increment is never larger than the
--   explicit one. Z3 needs dt ≥ 0; it holds for every dt.
-- * limiter_bounds_increment (srce.rs:600): under the limiter the increment is at most damax.
--   Z3's premises damax > 0 and 1 + afac * vd > 0 are not needed.
-- * limiter_vs_floor_0.5 (srce.rs:602): the floor of half a second can exceed the limiter's
--   step. A witness.
-- * split (srce.rs:604-605): the remaining time in idt equal parts.
-- * step (srce.rs:607-612): each pass moves forward and never past the end of the step.
--
-- Z3 takes the count idt as an integer. Its premises make idt larger than a positive ratio, so
-- here it is a natural number. The checks over IEEE f32 (groups U and S of Chaceon.scala) are
-- about the bits Rust computes; ℚ has no rounding, so they are not ported.
module PortAudit.TimeStep where

open import Data.Integer using (+_)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Product using (_×_; _,_)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _-_; _*_; -_; _≤_; _<_; _⊔_; _⊓_; ∣_∣)
open import Data.Rational.Base using (nonNegative; positive)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <-≤-trans; ≤-<-trans; <⇒≤; <⇒≢; <-irrefl; ≮⇒≥; _<?_; _≤?_;
         *-monoˡ-≤-nonNeg; *-monoʳ-≤-nonNeg; *-identityʳ; *-identityˡ; *-comm;
         0≤∣p∣; 0≤p⇒∣p∣≡p; ∣p*q∣≡∣p∣*∣q∣; ∣p∣≡0⇒p≡0; p≤p⊔q; p≤q⊔p; ⊔-lub; p⊓q≤q;
         p⊓q≤p; ⊔-sel; nonNegative⁻¹)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; :-_; con)
open import Data.Sum using (inj₁; inj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)
open import Relation.Nullary using (¬_; contradiction)
open import Relation.Nullary.Decidable using (from-yes)

open import ContextualBandit.Interface using (ofℕ; ofℕ-nonNeg)
open import OceanWaves.Order
  using (_/₀_; inv₀; inv₀-pos; inv₀-nonneg; inv₀-inverse; div-le-of-le-mul; div-mul-cancel;
         mul-div-cancel; div-nonneg; div-pos; div-le-div-of-cross; by-diff; ≤⇒0≤-; *-nonneg; *-pos)

private
  ≢0 : ∀ {q} → 0ℚ < q → q ≢ 0ℚ
  ≢0 0<q q≡0 = <⇒≢ 0<q (sym q≡0)

  0<1 : 0ℚ < 1ℚ
  0<1 = from-yes (0ℚ <? 1ℚ)

  -- |x / d| = |x| / d for d > 0.
  abs-div : ∀ x d → 0ℚ < d → ∣ x /₀ d ∣ ≡ ∣ x ∣ /₀ d
  abs-div x d 0<d = trans (∣p*q∣≡∣p∣*∣q∣ x (inv₀ d)) (cong (∣ x ∣ *_) (0≤p⇒∣p∣≡p (inv₀-nonneg (<⇒≤ 0<d))))

  ofℕ-suc-ge-1 : ∀ k → 1ℚ ≤ ofℕ (suc k)
  ofℕ-suc-ge-1 k = by-diff (ofℕ k) (solve 1 (λ x → con 1ℚ :+ x :- con 1ℚ := x) refl (ofℕ k))
                     (nonNegative⁻¹ (ofℕ k) {{ofℕ-nonNeg k}})

-- ---------------------------------------------------------------------------------------------
-- srce.rs:617, 623: einc1 = vs * dt / max(1, 1 - dt * vd).

denominator : (dt vd : ℚ) → ℚ
denominator dt vd = 1ℚ ⊔ (1ℚ - dt * vd)

einc1 : (vs vd dt : ℚ) → ℚ
einc1 vs vd dt = vs * dt /₀ denominator dt vd

implicit-le-explicit : ∀ vs vd dt → ∣ einc1 vs vd dt ∣ ≤ ∣ vs * dt ∣
implicit-le-explicit vs vd dt =
  subst (_≤ ∣ vs * dt ∣) (sym (abs-div (vs * dt) D 0<D))
    (div-le-of-le-mul {∣ vs * dt ∣} {D} {∣ vs * dt ∣} 0<D (subst (_≤ ∣ vs * dt ∣ * D) (*-identityʳ ∣ vs * dt ∣)
       (*-monoˡ-≤-nonNeg ∣ vs * dt ∣ {{nonNegative (0≤∣p∣ (vs * dt))}} 1≤D)))
  where
  D = denominator dt vd
  1≤D : 1ℚ ≤ D
  1≤D = p≤p⊔q 1ℚ (1ℚ - dt * vd)
  0<D : 0ℚ < D
  0<D = <-≤-trans 0<1 1≤D

-- ---------------------------------------------------------------------------------------------
-- srce.rs:598-600, the limiter, without its two clamps of 1e-10: afac = damax / |vs|, and
-- dt * (1 + afac * min(vd, 0)) ≤ afac. With vd ≤ 0 (the sign of damping) the increment of this
-- component is at most damax.

limiter-bounds-increment : ∀ damax vs vd dt afac →
  vs ≢ 0ℚ → vd ≤ 0ℚ → afac ≡ damax /₀ ∣ vs ∣ → 0ℚ ≤ dt → dt * (1ℚ + afac * vd) ≤ afac →
  ∣ vs * dt /₀ (1ℚ - dt * vd) ∣ ≤ damax
limiter-bounds-increment damax vs vd dt afac vs≢0 vd≤0 afac≡ 0≤dt limit =
  subst (_≤ damax) (sym (trans (abs-div (vs * dt) D 0<D)
                            (cong (_/₀ D) (trans (∣p*q∣≡∣p∣*∣q∣ vs dt) (cong (s *_) (0≤p⇒∣p∣≡p 0≤dt))))))
    (div-le-of-le-mul {s * dt} {D} {damax} 0<D sdt≤)
  where
  s = ∣ vs ∣
  D = 1ℚ - dt * vd
  0≤s : 0ℚ ≤ s
  0≤s = 0≤∣p∣ vs
  s≢0 : s ≢ 0ℚ
  s≢0 s≡0 = vs≢0 (∣p∣≡0⇒p≡0 vs s≡0)
  -- -dt * vd ≥ 0, so D ≥ 1.
  1≤D : 1ℚ ≤ D
  1≤D = by-diff (dt * (- vd)) (solve 2 (λ t v → con 1ℚ :- t :* v :- con 1ℚ := t :* (:- v)) refl dt vd)
          (*-nonneg 0≤dt (≤⇒0≤- vd≤0 |> λ h → subst (0ℚ ≤_) (solve 1 (λ v → con 0ℚ :- v := :- v) refl vd) h))
    where
    _|>_ : ∀ {A B : Set} → A → (A → B) → B
    x |> f = f x
  0<D : 0ℚ < D
  0<D = <-≤-trans 0<1 1≤D
  s-afac : s * afac ≡ damax
  s-afac = trans (cong (s *_) afac≡) (mul-div-cancel damax s≢0)
  scaled : s * dt + damax * dt * vd ≤ damax
  scaled = subst₂′ (solve 4 (λ s t a v → s :* (t :* (con 1ℚ :+ a :* v)) := s :* t :+ (s :* a) :* t :* v)
                     refl s dt afac vd
                    |> λ e → trans e (cong (λ c → s * dt + c * dt * vd) s-afac))
                   s-afac
                   (*-monoˡ-≤-nonNeg s {{nonNegative 0≤s}} limit)
    where
    _|>_ : ∀ {A B : Set} → A → (A → B) → B
    x |> f = f x
    subst₂′ : ∀ {a b c d} → a ≡ c → b ≡ d → a ≤ b → c ≤ d
    subst₂′ refl refl h = h
  sdt≤ : s * dt ≤ damax * D
  sdt≤ = by-diff (damax - (s * dt + damax * dt * vd))
           (solve 4 (λ m s t v → m :* (con 1ℚ :- t :* v) :- s :* t := m :- (s :* t :+ m :* t :* v))
              refl damax s dt vd)
           (≤⇒0≤- scaled)

-- srce.rs:602: dt = dt.max(0.5). The floor of half a second wins over the limiter when the
-- limit is smaller. With damax = 1/10, vs = 1 and vd = 0 the limiter allows 1/10 s, the floor
-- takes 1/2 s, and the increment is 1/2 > damax.
limiter-vs-floor-0·5 :
  let damax = + 1 / 10 ; vs = 1ℚ ; vd = 0ℚ ; afac = damax /₀ ∣ vs ∣
      dt = (afac /₀ (1ℚ + afac * vd)) ⊔ (+ 1 / 2) in
  dt ≡ + 1 / 2 × damax < ∣ vs * dt /₀ (1ℚ - dt * vd) ∣
limiter-vs-floor-0·5 = refl , from-yes (+ 1 / 10 <? ∣ 1ℚ * (+ 1 / 2) /₀ (1ℚ - + 1 / 2 * 0ℚ) ∣)

-- ---------------------------------------------------------------------------------------------
-- srce.rs:604-605: idt = 1 + trunc(0.99 * rem / dt); dt' = rem / idt, with rem = dtg - dttot.

c99 : ℚ
c99 = + 99 / 100

-- Z3's premises, with dtl the limited step and dtn the equal part.
record Split (rem dtl dtn : ℚ) (idt : ℕ) : Set where
  field
    0<rem     : 0ℚ < rem
    ½≤dtl     : + 1 / 2 ≤ dtl
    idt-1≤    : ofℕ idt - 1ℚ ≤ c99 * rem /₀ dtl
    ratio<idt : c99 * rem /₀ dtl < ofℕ idt
    dtn*idt   : dtn * ofℕ idt ≡ rem

module _ {rem dtl dtn : ℚ} {idt : ℕ} (split : Split rem dtl dtn idt) where
  open Split split
  private
    0<dtl : 0ℚ < dtl
    0<dtl = <-≤-trans (from-yes (0ℚ <? + 1 / 2)) ½≤dtl
    ratio-pos : 0ℚ < c99 * rem /₀ dtl
    ratio-pos = div-pos (*-pos (from-yes (0ℚ <? c99)) 0<rem) 0<dtl

  split-idt-ge-1 : 1ℚ ≤ ofℕ idt
  split-idt-ge-1 = go idt ratio<idt
    where
    go : ∀ k → c99 * rem /₀ dtl < ofℕ k → 1ℚ ≤ ofℕ k
    go zero    r<0 = contradiction (<-trans′ ratio-pos r<0) (<-irrefl refl)
      where open import Data.Rational.Properties using () renaming (<-trans to <-trans′)
    go (suc k) _   = ofℕ-suc-ge-1 k

  private
    0<idt : 0ℚ < ofℕ idt
    0<idt = <-≤-trans 0<1 split-idt-ge-1
    dtn≡ : dtn ≡ rem /₀ ofℕ idt
    dtn≡ = trans (sym (div-mul-cancel′ dtn)) (cong (_/₀ ofℕ idt) dtn*idt)
      where
      -- dtn * idt / idt = dtn
      div-mul-cancel′ : ∀ a → a * ofℕ idt /₀ ofℕ idt ≡ a
      div-mul-cancel′ a = trans (solve 3 (λ a b ib → a :* b :* ib := a :* (b :* ib)) refl a (ofℕ idt) (inv₀ (ofℕ idt)))
                                (trans (cong (a *_) (inv₀-inverse (ofℕ idt) (≢0 0<idt))) (*-identityʳ a))

  split-le-rem : dtn ≤ rem
  split-le-rem = subst (_≤ rem) (sym dtn≡)
    (div-le-of-le-mul {rem} {ofℕ idt} {rem} 0<idt (subst (_≤ rem * ofℕ idt) (*-identityʳ rem)
       (*-monoˡ-≤-nonNeg rem {{nonNegative (<⇒≤ 0<rem)}} split-idt-ge-1)))

  split-le-dt/0·99 : dtn ≤ dtl /₀ c99
  split-le-dt/0·99 = subst (_≤ dtl /₀ c99) (sym dtn≡)
    (div-le-div-of-cross {rem} {ofℕ idt} {dtl} {c99} 0<idt (from-yes (0ℚ <? c99)) cross)
    where
    -- ratio * dtl = 0.99 rem, and ratio < idt.
    cross : rem * c99 ≤ dtl * ofℕ idt
    cross = subst₂′ (trans (div-mul-cancel (c99 * rem) (≢0 0<dtl)) (*-comm c99 rem)) (*-comm (ofℕ idt) dtl)
              (*-monoʳ-≤-nonNeg dtl {{nonNegative (<⇒≤ 0<dtl)}} (<⇒≤ ratio<idt))
      where
      subst₂′ : ∀ {a b c d} → a ≡ c → b ≡ d → a ≤ b → c ≤ d
      subst₂′ refl refl h = h

-- split_le_dt, refuted: the 0.99 lets an equal part exceed the limited step. With rem = 201/200
-- and dtl = 1, 0.99 rem / dtl = 0.99495, so idt = 1 and dtn = rem > dtl.
split-le-dt-refuted : Split (+ 201 / 200) 1ℚ (+ 201 / 200) 1 × 1ℚ < + 201 / 200
split-le-dt-refuted =
  record { 0<rem     = from-yes (0ℚ <? + 201 / 200)
         ; ½≤dtl     = from-yes (+ 1 / 2 ≤? 1ℚ)
         ; idt-1≤    = from-yes (ofℕ 1 - 1ℚ ≤? c99 * (+ 201 / 200) /₀ 1ℚ)
         ; ratio<idt = from-yes (c99 * (+ 201 / 200) /₀ 1ℚ <? ofℕ 1)
         ; dtn*idt   = refl } ,
  from-yes (1ℚ <? + 201 / 200)

-- ---------------------------------------------------------------------------------------------
-- srce.rs:607-612: dt'' = max(dt', min(dtmin, rem)), dttot += dt''.

least : (dtmin rem : ℚ) → ℚ
least dtmin rem = dtmin ⊓ rem

dtf : (dtn dtmin rem : ℚ) → ℚ
dtf dtn dtmin rem = dtn ⊔ least dtmin rem

step-never-past-dtg : ∀ {rem dtl dtn idt} → Split rem dtl dtn idt → ∀ dtmin → dtf dtn dtmin rem ≤ rem
step-never-past-dtg split dtmin = ⊔-lub (split-le-rem split) (p⊓q≤q dtmin _)

step-progress : ∀ dtn dtmin rem → least dtmin rem ≤ dtf dtn dtmin rem
step-progress dtn dtmin rem = p≤q⊔p dtn (least dtmin rem)
