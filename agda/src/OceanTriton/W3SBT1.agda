{-# OPTIONS --safe --without-K #-}

-- Milestone M4 of ocean-triton/PLAN.md: WAVEWATCH III's bottom friction W3SBT1 (the JONSWAP
-- form), read from model/src/w3sbt1md.F90 of metocean/WW3 at tag 7.14.mos-92e2cf6, commit
-- 92e2cf66, and written here line by line.
--
--     w3sbt1md.F90:175   IF ( DEPTH*WN(1) .GT. 6 ) THEN  D = 0.  S = 0.      (deep water)
--     w3sbt1md.F90:186   FACTOR = SBTC1 / DEPTH
--     w3sbt1md.F90:194   DO IK=1, NK
--     w3sbt1md.F90:195     IF ( WN(IK)*DEPTH .GT. 6. ) EXIT
--     w3sbt1md.F90:196     CBETA(IK) = FACTOR * MAX(0., (CG(IK)*WN(IK)/SIG(IK)-0.5) )
--     w3sbt1md.F90:202   NSCUT = (IK-1)*NTH
--     w3sbt1md.F90:204   D(IS) = CBETA(MAPWN(IS)) for IS ≤ NSCUT, 0 above      (:204-210)
--     w3sbt1md.F90:212   S = D * A
--
-- Indices here start at 0: ik here is IK - 1, and the arrays wn, cg, sig are WN, CG, SIG read
-- from IK = 1. MAPWN(IS) is the bin of the spectral point IS. Fortran's REAL is ℚ here (exact);
-- the kernel runs in float32 like the Fortran, which the replay of M5 compares.
--
-- The loop with EXIT writes CBETA(IK) for the IK before the first one in deep water, and the
-- spectral points of those bins are the first NSCUT. `alive ik` says that no IK up to ik exited.
--
-- The kernel has no loop: lane IS tests its own bin, D = FACTOR max(0, …) where
-- WN DEPTH ≤ 6, else 0. `sbtD-sound`: when WN increases with IK (as on every WW3 frequency
-- grid) and DEPTH ≥ 0, this is the routine's D for every spectral point; `sbtS-sound`, its S.
module OceanTriton.W3SBT1 where

open import Data.Bool using (Bool; true; false; if_then_else_; not; _∧_)
open import Data.Fin using (#_)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; z≤n; s≤s)
import Data.Nat.Properties as ℕP
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _⊔_; _≤_; _<_; _≤?_; _<?_; NonNegative)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Properties using (≤-trans; ≤-reflexive; <-irrefl; <-≤-trans; ≰⇒>; *-monoʳ-≤-nonNeg; *-comm)
open import Data.Vec using ([]; _∷_)
open import Relation.Nullary using (Dec; yes; no; does; ¬_)
open import Data.Bool.Properties using (∧-zeroʳ; ∧-identityʳ)
open import Data.Bool using (T)
open import Data.Unit using (tt)
open import Relation.Nullary.Decidable using (dec-true; dec-false; toWitness)
open import Relation.Nullary.Negation using (contradiction)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; subst)

open import OceanWaves.Order using (_/₀_; lit)
open import OceanTriton.Gather

½ : ℚ
½ = 1ℚ /₀ lit 2

-- The routine's inputs: the spectrum A over the spectral points, and the bins' wn, cg, sig.
record Bottom : Set where
  field
    sbtc1 depth : ℚ
    wn cg sig   : ℕ → ℚ
    mapwn       : ℕ → ℕ
    A           : ℕ → ℚ
open Bottom

module _ (B : Bottom) where

  -- IF ( WN(IK)*DEPTH .GT. 6. ) EXIT   (:195)
  exits : ℕ → Bool
  exits ik = does (lit 6 <? wn B ik * depth B)

  -- No IK up to ik exited the loop.
  alive : ℕ → Bool
  alive zero     = not (exits zero)
  alive (suc ik) = alive ik ∧ not (exits (suc ik))

  -- FACTOR (:186) and CBETA(IK) (:196).
  factor : ℚ
  factor = sbtc1 B /₀ depth B

  cbeta : ℕ → ℚ
  cbeta ik = factor * (0ℚ ⊔ (cg B ik * wn B ik /₀ sig B ik - ½))

  -- D(IS) (:175-210) and S (:212).
  sbtD : ℕ → ℚ
  sbtD is = if does (lit 6 <? depth B * wn B 0) then 0ℚ
            else (if alive (mapwn B is) then cbeta (mapwn B is) else 0ℚ)

  sbtS : ℕ → ℚ
  sbtS is = sbtD is * A B is

-- ---------------------------------------------------------------------------------------------
-- The kernels

private
  dExpr : ExprG 4 1 2
  dExpr = ifLe (gat wn′ m ⊗ par d) (con (lit 6))
               (par s ⊘ par d ⊗ max (con 0ℚ) (gat cg′ m ⊗ gat wn′ m ⊘ gat sig′ m ⊖ con ½))
               (con 0ℚ)
    where wn′ = # 1 ; cg′ = # 2 ; sig′ = # 3 ; m = # 0 ; s = # 0 ; d = # 1

sbtDK sbtSK : KernelG
sbtDK = record
  { name = "w3sbt1_d" ; na = 4 ; ni = 1 ; ns = 2 ; nr = 0
  ; arrays = "A" ∷ "wn" ∷ "cg" ∷ "sig" ∷ [] ; idxs = "mapwn" ∷ [] ; scalars = "sbtc1" ∷ "depth" ∷ []
  ; sums = [] ; reds = [] ; body = dExpr
  ; doc = "the diagonal D of WAVEWATCH III's JONSWAP bottom friction W3SBT1 (w3sbt1md.F90:175-210)" }
sbtSK = record
  { name = "w3sbt1_s" ; na = 4 ; ni = 1 ; ns = 2 ; nr = 0
  ; arrays = "A" ∷ "wn" ∷ "cg" ∷ "sig" ∷ [] ; idxs = "mapwn" ∷ [] ; scalars = "sbtc1" ∷ "depth" ∷ []
  ; sums = [] ; reds = [] ; body = dExpr ⊗ at (# 0)
  ; doc = "the source S = D A of WAVEWATCH III's JONSWAP bottom friction W3SBT1 (w3sbt1md.F90:212)" }

sbtStore : Bottom → StoreG 4 1 2
sbtStore B = sg (A B ∷ wn B ∷ cg B ∷ sig B ∷ []) (mapwn B ∷ []) (sbtc1 B ∷ depth B ∷ [])

-- WN does not decrease over the bins 0 … nk - 1.
Increasing : ℕ → (ℕ → ℚ) → Set
Increasing nk w = ∀ i j → i ℕ.≤ j → j ℕ.< nk → w i ≤ w j

private
  -- What a decision says, as a Boolean.
  lt-true : ∀ {p q : ℚ} → p < q → does (p <? q) ≡ true
  lt-true {p} {q} h = dec-true (p <? q) h

  lt-false : ∀ {p q : ℚ} → ¬ (p < q) → does (p <? q) ≡ false
  lt-false {p} {q} h = dec-false (p <? q) h

  lt-sound : ∀ {p q : ℚ} → does (p <? q) ≡ true → p < q
  lt-sound {p} {q} = aux (p <? q)
    where
    aux : (d : Dec (p < q)) → does d ≡ true → p < q
    aux (yes h) _ = h
    aux (no _) ()

  -- x > 6 is the negation of x ≤ 6.
  gt-not-le : ∀ x → does (lit 6 <? x) ≡ not (does (x ≤? lit 6))
  gt-not-le x = aux (x ≤? lit 6)
    where
    aux : (d : Dec (x ≤ lit 6)) → does (lit 6 <? x) ≡ not (does d)
    aux (yes p) = lt-false (λ q → <-irrefl refl (<-≤-trans q p))
    aux (no  p) = lt-true (≰⇒> p)

  le-false : ∀ {x} → lit 6 < x → does (x ≤? lit 6) ≡ false
  le-false {x} h = dec-false (x ≤? lit 6) (λ p → <-irrefl refl (<-≤-trans h p))

  -- The case analysis of D, on Booleans.
  pick-d : ∀ (b₁ b₂ : Bool) (C : ℚ) → (b₂ ≡ true → b₁ ≡ false) →
    (if b₁ then C else 0ℚ) ≡ (if b₂ then 0ℚ else (if not (not b₁) then C else 0ℚ))
  pick-d true  true  C h with h refl
  ... | ()
  pick-d true  false C h = refl
  pick-d false true  C h = refl
  pick-d false false C h = refl

module _ (B : Bottom) (nk : ℕ) (inc : Increasing nk (wn B)) (hd : 0ℚ ≤ depth B) where

  private
    instance _ = nonNegative hd

    -- A bin above a shallow one is shallower or as deep, in kD.
    kd-mono : ∀ i j → i ℕ.≤ j → j ℕ.< nk → wn B i * depth B ≤ wn B j * depth B
    kd-mono i j h hj = *-monoʳ-≤-nonNeg (depth B) (inc i j h hj)

    -- With WN increasing, `alive ik` is the test of bin ik alone.
    alive-one : ∀ ik → ik ℕ.< nk → alive B ik ≡ not (exits B ik)
    alive-one zero     _ = refl
    alive-one (suc ik) h = aux (lit 6 <? wn B (suc ik) * depth B)
      where
      aux : Dec (lit 6 < wn B (suc ik) * depth B) → alive B (suc ik) ≡ not (exits B (suc ik))
      aux (yes p) = trans (cong (λ b → alive B ik ∧ not b) (lt-true p))
                    (trans (∧-zeroʳ (alive B ik)) (cong not (sym (lt-true p))))
      aux (no p) = trans (cong (λ b → alive B ik ∧ not b) (lt-false p))
                   (trans (∧-identityʳ (alive B ik))
                   (trans (alive-one ik (ℕP.<-trans (ℕP.n<1+n ik) h))
                   (trans (cong not (lt-false p′)) (cong not (sym (lt-false p))))))
        where p′ = λ q → p (<-≤-trans q (kd-mono ik (suc ik) (ℕP.n≤1+n ik) h))

  -- The kernel's D is the routine's D at every spectral point of a bin below nk.
  sbtD-sound : ∀ n is → mapwn B is ℕ.< nk → runG sbtDK n (sbtStore B) is ≡ sbtD B is
  sbtD-sound n is hm =
    trans (pick-d (does (x ≤? lit 6)) (does (lit 6 <? depth B * wn B 0)) (cbeta B ik) deep⇒no)
          (cong (λ b → if does (lit 6 <? depth B * wn B 0) then 0ℚ else (if b then cbeta B ik else 0ℚ))
                (sym (trans (alive-one ik hm) (cong not (gt-not-le x)))))
    where
    ik = mapwn B is
    x  = wn B ik * depth B
    deep⇒no : does (lit 6 <? depth B * wn B 0) ≡ true → does (x ≤? lit 6) ≡ false
    deep⇒no e = le-false (<-≤-trans (lt-sound e)
                  (≤-trans (≤-reflexive (*-comm (depth B) (wn B 0))) (kd-mono 0 ik z≤n hm)))

  sbtS-sound : ∀ n is → mapwn B is ℕ.< nk → runG sbtSK n (sbtStore B) is ≡ sbtS B is
  sbtS-sound n is hm = cong (_* A B is) (sbtD-sound n is hm)

sbtKernels : List KernelG
sbtKernels = sbtDK ∷ sbtSK ∷ []
