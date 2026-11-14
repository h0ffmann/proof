{-# OPTIONS --safe --without-K #-}

-- Milestone M3 of ocean-triton/PLAN.md, step 3b: advection in frequency (in k, across the bins
-- of the spectrum) with a Courant number of its own on every face, and closed ends.
--
-- The spectrum is NTH directions by NK bins, stored as WW3 stores it: the point i is the
-- direction i % NTH of the bin i / NTH (IS = ITH + (IK-1) NTH, from 0 here). Along each direction
-- the step is `OceanWaves.Advection.advect` on the column of the bins, with
--
--     μ k      the Courant number of face k (face k below bin k, face NK above the last), and
--     b = 0    nothing enters below the first bin;
--
-- the top is closed when μ NK = 0, which the host writes. `freq-total`: the column keeps its
-- total; `freq-nonneg`: under the CFL condition it stays non-negative.
--
-- The kernel has one lane per point, and reads through three index arrays and a mask that the
-- host lays out (`freqStore`): kof = i / NTH, kof1 = i / NTH + 1, up = i - NTH (the point of the
-- same direction one bin down), msk = 0 on the first bin and 1 above it.
--
--     N'(i) = N(i) + μ(kof i) (msk(i) N(up i)) - μ(kof1 i) N(i)
--
-- `freqK-sound`: it is the column's `advect` at every point, for every NTH > 0, μ and N.
module OceanTriton.Freq where

open import Data.Bool using (if_then_else_; true; false)
open import Data.Fin using (#_)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _<ᵇ_)
import Data.Nat.Properties as ℕP
open import Data.Nat.DivMod using (_/_; _%_; m≡m%n+[m/n]*n; m/n≡0⇒m<n)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_)
open import Data.Rational.Properties using (*-zeroˡ; *-zeroʳ; *-identityˡ; +-identityʳ)
open import Data.Vec using ([]; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; cong₂; subst)
open import Relation.Nullary using (¬_)
open import Relation.Nullary.Negation using (contradiction)

open import OceanWaves.Advection using (advect; upstream; upFlux; advect-sum; advect-nonneg; CFL)
open import OceanWaves.Sums using (sumTo)
open import OceanTriton.Gather

-- The column of direction θ: its value in bin k.
column : ℕ → (ℕ → ℚ) → ℕ → ℕ → ℚ
column nth N θ k = N (θ ℕ.+ k ℕ.* nth)

-- The model: point i moves with the column of its direction.
freqStep : ℕ → (ℕ → ℚ) → (ℕ → ℚ) → ℕ → ℚ
freqStep nth μ N i = advect μ 0ℚ (column nth N (i % nth′)) (i / nth′)
  where nth′ = suc (nth ∸ 1)

-- ---------------------------------------------------------------------------------------------
-- The kernel

freqK : KernelG
freqK = record
  { name = "freq_advect" ; na = 3 ; ni = 3 ; ns = 0 ; nr = 0
  ; arrays = "N" ∷ "mu" ∷ "msk" ∷ [] ; idxs = "kof" ∷ "kof1" ∷ "up" ∷ [] ; scalars = []
  ; sums = [] ; reds = []
  ; body = at n ⊕ gat mu kof ⊗ (at msk ⊗ gat n up) ⊖ gat mu kof1 ⊗ at n
  ; doc = "upwind advection in frequency with a Courant number per face and closed ends (OceanTriton.Freq.freqStep)" }
  where n = # 0 ; mu = # 1 ; msk = # 2 ; kof = # 0 ; kof1 = # 1 ; up = # 2

-- What the host lays out, for NTH = suc t.
freqStore : ℕ → (ℕ → ℚ) → (ℕ → ℚ) → StoreG 3 3 0
freqStore t μ N = sg (N ∷ μ ∷ msk ∷ []) ((λ i → i / suc t) ∷ (λ i → suc (i / suc t)) ∷ (λ i → i ∸ suc t) ∷ []) []
  where msk = λ i → if i <ᵇ suc t then 0ℚ else 1ℚ

module _ (t : ℕ) (μ N : ℕ → ℚ) where

  private
    nth = suc t

    -- i is its direction plus its bin times NTH.
    split : ∀ i → i ≡ i % nth ℕ.+ (i / nth) ℕ.* nth
    split i = m≡m%n+[m/n]*n i nth

    -- One bin down, in the same direction.
    down : ∀ θ k → θ ℕ.+ suc k ℕ.* nth ∸ nth ≡ θ ℕ.+ k ℕ.* nth
    down θ k = trans (cong (_∸ nth) (eq θ nth k)) (ℕP.m+n∸n≡m (θ ℕ.+ k ℕ.* nth) nth)
      where
      open import Data.Nat.Solver using (module +-*-Solver)
      open +-*-Solver using (solve; _:=_; _:+_; _:*_)
      eq : ∀ θ n k → θ ℕ.+ (n ℕ.+ k ℕ.* n) ≡ θ ℕ.+ k ℕ.* n ℕ.+ n
      eq = solve 3 (λ θ n k → θ :+ (n :+ k :* n) := θ :+ k :* n :+ n) refl

    -- The mask and the upstream read are the column's upstream value.
    inflow : ∀ i → (if i <ᵇ nth then 0ℚ else 1ℚ) * N (i ∸ nth)
                 ≡ upstream 0ℚ (column nth N (i % nth)) (i / nth)
    inflow i with i / nth in hk
    ... | zero = trans (cong (λ b → (if b then 0ℚ else 1ℚ) * N (i ∸ nth)) (lt-true (m/n≡0⇒m<n {i} {nth} hk)))
                       (*-zeroˡ (N (i ∸ nth)))
      where
      lt-true : ∀ {m n} → m ℕ.< n → (m <ᵇ n) ≡ true
      lt-true {m} {n} h with m <ᵇ n | ℕP.<⇒<ᵇ h
      ... | true | _ = refl
    ... | suc k = trans (cong (λ b → (if b then 0ℚ else 1ℚ) * N (i ∸ nth)) (lt-false above))
                  (trans (*-identityˡ (N (i ∸ nth)))
                         (cong N (trans (cong (_∸ nth) i≡) (down (i % nth) k))))
      where
      i≡ : i ≡ i % nth ℕ.+ suc k ℕ.* nth
      i≡ = trans (split i) (cong (λ q → i % nth ℕ.+ q ℕ.* nth) hk)
      above : ¬ (i ℕ.< nth)
      above h = ℕP.<⇒≱ h (subst (nth ℕ.≤_) (sym i≡)
                  (ℕP.≤-trans (ℕP.m≤n+m nth (i % nth)) (ℕP.+-monoʳ-≤ (i % nth) (ℕP.m≤m+n nth (k ℕ.* nth)))))
      lt-false : ∀ {m n} → ¬ (m ℕ.< n) → (m <ᵇ n) ≡ false
      lt-false {m} {n} h with m <ᵇ n in e
      ... | false = refl
      ... | true  = contradiction (ℕP.<ᵇ⇒< m n (subst (λ b → Data.Bool.T b) (sym e) Data.Unit.tt)) h
        where import Data.Bool; import Data.Unit

  -- The kernel is the model at every point.
  freqK-sound : ∀ n i → runG freqK n (freqStore t μ N) i ≡ freqStep nth μ N i
  freqK-sound n i =
    cong₂ (λ c u → c + μ (i / nth) * u - μ (suc (i / nth)) * c) (cong N (split i)) (inflow i)

-- ---------------------------------------------------------------------------------------------
-- The physics, restated for the columns

-- Closed ends: nothing enters below the first bin, and with μ nk = 0 nothing leaves above the
-- last, so each direction keeps its total over the nk bins.
freq-total : ∀ nk μ (col : ℕ → ℚ) → μ nk ≡ 0ℚ → sumTo nk (advect μ 0ℚ col) ≡ sumTo nk col
freq-total nk μ col h =
  trans (advect-sum nk μ 0ℚ col)
    (trans (cong₂ (λ a b → sumTo nk col + a - b) (*-zeroʳ (μ 0)) (trans (cong (_* upstream 0ℚ col nk) h) (*-zeroˡ (upstream 0ℚ col nk))))
           (trans (cong (_- 0ℚ) (+-identityʳ (sumTo nk col))) (sub0 (sumTo nk col))))
  where
  open import Data.Rational.Solver using (module +-*-Solver)
  open +-*-Solver using (solve; _:=_; _:-_; con)
  sub0 : ∀ x → x - 0ℚ ≡ x
  sub0 = solve 1 (λ x → x :- con 0ℚ := x) refl

-- Positivity under the CFL condition on the faces 0 … nk.
freq-nonneg : ∀ nk μ (col : ℕ → ℚ) → CFL nk μ → (∀ k → k ℕ.< nk → 0ℚ ≤ col k) →
              ∀ k → k ℕ.< nk → 0ℚ ≤ advect μ 0ℚ col k
freq-nonneg nk μ col hcfl hcol = advect-nonneg nk μ 0ℚ col hcfl (Data.Rational.Properties.≤-refl) hcol
  where import Data.Rational.Properties

freqKernels : List KernelG
freqKernels = freqK ∷ []
