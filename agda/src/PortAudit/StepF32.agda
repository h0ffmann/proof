{-# OPTIONS --safe --without-K #-}

-- Group S of the port audit of chaceon (`tools/port-audit/Chaceon.hs`), the part over IEEE f32
-- (`PortAudit.Float32`): the time step of W3SRCE in rust/crates/ww3-kernels/src/srce.rs at the
-- commit that `Chaceon.hs` pins. `PortAudit.TimeStep` has the part over the reals. The names
-- follow Z3, with `-` for `_`.
--
-- * spectrum_nonneg (srce.rs:619, 624, 629, 742): `(sp + einc).max(0.)` is never negative and
--   never NaN, for every f32 sp and einc, NaN and infinity included. It holds for every float in
--   place of the sum, and for both answers that maxNum may give on +0 and -0.
-- * limited_step_le_dam and limited_step_sign (srce.rs:617-618): the limited increment
--   `sign(min(dam, |einc1|), einc1)` is at most dam and keeps the sign of einc1.
-- * tail_no_negative_zero (srce.rs:671-675): the `+ 0.` of the high-frequency tail turns -0
--   into +0. It holds for every float in place of the product.
module PortAudit.StepF32 where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; _xor_)
open import Data.Bool.Properties using (∧-zeroʳ; ∨-zeroʳ)
open import Data.Nat using (ℕ; zero; suc; _+_)
import Data.Nat.Properties as ℕₚ
open import Data.Product using (proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import PortAudit.Float32
open import PortAudit.Float32Exact
open import PortAudit.Intrinsics using (fsign; fsignB)

-- ---------------------------------------------------------------------------------------------
-- spectrum_nonneg (srce.rs:619)

private
  -- not NaN and ≥ 0, read from the kind of a float.
  NonNeg : Kind → Bool
  NonNeg k = not (isNaNK k) ∧ not (isNaNK k) ∧ not (ltK k (fin false 0))

  max-ok : ∀ z y k → classify y ≡ k →
           NonNeg (classify (fmaxB z y zeroF (isNaNK k) false (ltK k (fin false 0)) (ltK (fin false 0) k))) ≡ true
  max-ok z y nan             eq = refl
  max-ok z y (inf true)      eq = refl
  max-ok z y (inf false)     eq = cong NonNeg eq
  max-ok z y (fin false zero) eq with z
  ... | true  = cong NonNeg eq
  ... | false = refl
  max-ok z y (fin false (suc m)) eq = cong NonNeg eq
  max-ok z y (fin true zero) eq with z
  ... | true  = cong NonNeg eq
  ... | false = refl
  max-ok z y (fin true (suc m)) eq = refl

-- `z` is the answer that maxNum gives for +0 and -0: the statement holds for both.
spectrum-nonneg : ∀ z sp einc → let updated = fmax z (add sp einc) zeroF in
                  (not (isNaN updated) ∧ ge updated zeroF) ≡ true
spectrum-nonneg z sp einc = max-ok z (add sp einc) _ refl

-- ---------------------------------------------------------------------------------------------
-- limited_step_le_dam, limited_step_sign (srce.rs:618)

-- einc2 = sign(min(dam, |einc1|), einc1).
limited : Bool → Float32 → Float32 → Float32
limited z einc dam = fsign (fmin z dam (abs einc)) einc

private
  abs-fsignB : ∀ m b → abs (fsignB m b) ≡ abs m
  abs-fsignB m true  = refl
  abs-fsignB m false = refl

  -- |dam| ≤ dam for dam ≥ 0.
  LeAbs : Kind → Kind → Bool
  LeAbs a b = not (isNaNK a) ∧ not (isNaNK b) ∧ not (ltK b a)

  le-abs-self-k : ∀ k → (not (isNaNK k) ∧ not (ltK k (fin false 0))) ≡ true → LeAbs (absK k) k ≡ true
  le-abs-self-k nan               ()
  le-abs-self-k (inf true)        ()
  le-abs-self-k (inf false)       _ = refl
  le-abs-self-k (fin false m)     _ rewrite n<ᵇn m = refl
  le-abs-self-k (fin true zero)   _ = refl
  le-abs-self-k (fin true (suc m)) ()

  le-abs-self : ∀ dam → ge dam zeroF ≡ true → le (abs dam) dam ≡ true
  le-abs-self dam p = trans (cong (λ a → LeAbs a (classify dam)) (classify-abs dam)) (le-abs-self-k (classify dam) p)

  le-fmin : ∀ z dam ae → ge dam zeroF ≡ true → isNaN dam ≡ false → ∀ b₀ b₁ b₂ b₃ →
            isNaN dam ≡ b₀ → isNaN ae ≡ b₁ → lt dam ae ≡ b₂ → lt ae dam ≡ b₃ → abs ae ≡ ae →
            le (abs (fminB z dam ae b₀ b₁ b₂ b₃)) dam ≡ true
  le-fmin z dam ae p n true  b₁    b₂    b₃    e₀ _  _  _  _ = case (trans (sym n) e₀)
    where case : false ≡ true → _
          case ()
  le-fmin z dam ae p n false true  b₂    b₃    _  _  _  _  _ = le-abs-self dam p
  le-fmin z dam ae p n false false true  b₃    _  _  _  _  _ = le-abs-self dam p
  le-fmin z dam ae p n false false false true  e₀ e₁ e₂ _ aa =
    subst (λ u → le u dam ≡ true) (sym aa) (le-ae e₀ e₁ e₂)
    where
      le-ae : isNaN dam ≡ false → isNaN ae ≡ false → lt dam ae ≡ false → le ae dam ≡ true
      le-ae e₀ e₁ e₂ rewrite e₀ | e₁ | e₂ = refl
  le-fmin true  dam ae p n false false false false _ _ _ _ _ = le-abs-self dam p
  le-fmin false dam ae p n false false false false e₀ e₁ e₂ _ aa =
    subst (λ u → le u dam ≡ true) (sym aa) (le-ae e₀ e₁ e₂)
    where
      le-ae : isNaN dam ≡ false → isNaN ae ≡ false → lt dam ae ≡ false → le ae dam ≡ true
      le-ae e₀ e₁ e₂ rewrite e₀ | e₁ | e₂ = refl

limited-step-le-dam : ∀ z einc dam → ge dam zeroF ≡ true → isNaN dam ≡ false →
                      le (abs (limited z einc dam)) dam ≡ true
limited-step-le-dam z einc dam p n =
  trans (cong (λ u → le u dam) (abs-fsignB (fmin z dam (abs einc)) (isNegative einc)))
        (le-fmin z dam (abs einc) p n _ _ _ _ refl refl refl refl refl)

private
  -- min(dam, x) is not NaN when dam is not.
  fmin-not-nan : ∀ z x y b₀ b₁ b₂ b₃ → isNaN x ≡ b₀ → isNaN y ≡ b₁ → isNaN x ≡ false →
                 isNaN (fminB z x y b₀ b₁ b₂ b₃) ≡ false
  fmin-not-nan z x y true  b₁    b₂    b₃    e₀ _  n = case (trans (sym n) e₀)
    where case : false ≡ true → _
          case ()
  fmin-not-nan z x y false true  b₂    b₃    _  _  n = n
  fmin-not-nan z x y false false true  b₃    _  _  n = n
  fmin-not-nan z x y false false false true  _  e₁ _ = e₁
  fmin-not-nan true  x y false false false false _ _ n = n
  fmin-not-nan false x y false false false false _ e₁ _ = e₁

  isNeg-neg-abs : ∀ k → isNaNK k ≡ false → isNegativeK (negK (absK k)) ≡ true
  isNeg-neg-abs (inf s)   _ = refl
  isNeg-neg-abs (fin s m) _ = refl

  isNeg-abs : ∀ k → isNegativeK (absK k) ≡ false
  isNeg-abs nan       = refl
  isNeg-abs (inf s)   = refl
  isNeg-abs (fin s m) = refl

  isNaN-abs : ∀ k → isNaNK (absK k) ≡ isNaNK k
  isNaN-abs nan       = refl
  isNaN-abs (inf s)   = refl
  isNaN-abs (fin s m) = refl

  -- The sign of fsignB m b is b, for m not NaN.
  sign-of : ∀ m b → isNaN m ≡ false → isNegative (fsignB m b) ≡ b
  sign-of m true  n = trans (cong isNegativeK (trans (classify-neg (abs m)) (cong negK (classify-abs m))))
                            (isNeg-neg-abs (classify m) n)
  sign-of m false n = trans (cong isNegativeK (classify-abs m)) (isNeg-abs (classify m))

  same : ∀ b → not (b xor b) ≡ true
  same true  = refl
  same false = refl

-- The limited step keeps the sign of the unlimited one: SBV's .== on two SBools is `not xor`.
limited-step-sign : ∀ z einc dam → ge dam zeroF ≡ true → isNaN dam ≡ false → isNaN einc ≡ false →
                    isZero einc ≡ false →
                    (isZero (limited z einc dam) ∨ not (isNegative (limited z einc dam) xor isNegative einc)) ≡ true
limited-step-sign z einc dam _ n _ _ =
  trans (cong (isZero (limited z einc dam) ∨_)
              (cong (λ b → not (b xor isNegative einc))
                    (sign-of (fmin z dam (abs einc)) (isNegative einc)
                             (fmin-not-nan z dam (abs einc) _ _ _ _ refl refl n))))
        (trans (cong (isZero (limited z einc dam) ∨_) (same (isNegative einc))) (∨-zeroʳ _))

-- ---------------------------------------------------------------------------------------------
-- tail_no_negative_zero (srce.rs:673)

private
  NotNegZero : Kind → Bool
  NotNegZero k = not (isZeroK k ∧ isNegativeK k)

  plus-zero : ∀ y k → classify y ≡ k → NotNegZero (classify (addK y zeroF k (fin false 0))) ≡ true
  plus-zero y nan              eq = refl
  plus-zero y (inf s)          eq = cong NotNegZero eq
  plus-zero y (fin false m)    eq =
    trans (cong NotNegZero (round-exact false (m + 0) (subst Repr (sym (ℕₚ.+-identityʳ m)) (proj₂ (classify-fin y eq)))))
          (cong not (∧-zeroʳ _))
  plus-zero y (fin true zero)  eq = cong NotNegZero (cancel-eq true 0 false 0 refl)
  plus-zero y (fin true (suc m)) eq =
    cong NotNegZero (cancel-gt true (suc m) false 0 (ℕₚ.0<1+n) (proj₂ (classify-fin y eq)))

tail-no-negative-zero : ∀ sp fachfa → ge sp zeroF ≡ true → ge fachfa zeroF ≡ true →
                        let tailV = add (mul sp fachfa) zeroF in
                        not (isZero tailV ∧ isNegative tailV) ≡ true
tail-no-negative-zero sp fachfa _ _ = plus-zero (mul sp fachfa) _ refl
