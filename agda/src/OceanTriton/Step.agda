{-# OPTIONS --safe --without-K #-}

-- More of one model step as Triton kernels, with their soundness theorems (milestone M1 of
-- ocean-triton/PLAN.md):
--
-- * `snl`: the quadruplet transfer of `OceanWaves.Sources` as a three-point stencil on the gated
--   exchange amounts, proved equal to the sum over all centres (`snl-stencil`), so it keeps the
--   total action (`snlK-conserves`);
-- * `source_step_snl`: the whole source step with S_nl computed in the kernel, so no input array
--   holds S_nl any more;
-- * `wavenumber`: the dispersion solver of `OceanWaves.Bisection`, a loop kernel with two
--   registers per lane, proved equal to `waveNumber` for every number of steps;
-- * `sxx`, `sxy`, `syy`: the radiation stress of `WaveTheory.RadiationStress`, the output fields
--   SXX, SXY and SYY of WAVEWATCH III.
module OceanTriton.Step where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Fin using (#_)
open import Data.List as L using (List)
open import Data.Nat as ℕ using (ℕ; zero; suc; _≡ᵇ_)
import Data.Nat.Properties as ℕP
open import Data.Product using (_×_; _,_; proj₁; proj₂)
import Data.Rational
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _<?_)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Data.Vec using (Vec; []; _∷_)
open import Relation.Nullary using (Dec; yes; no; does; contradiction)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; cong₂)

open import OceanWaves.Order using (_/₀_; lit; 2ℚ)
open import OceanWaves.Sums using (sumTo; sumTo-congr; sumTo-add; sumTo-sub; sumTo-zero-fn; pick; sumTo-pick; eqb-true)
open import OceanWaves.Sources
  using (gate; interior?; quad; snl; snl-conserves-action; linStep; limit; sourceStep)
open import OceanWaves.Dispersion using (Medium; padeModel; padeT; sigma2)
open import OceanWaves.Bisection using (bisect; bisect-step; mid; waveNumber)
open import WaveTheory.RadiationStress using (Direction; cs; sn; ½; Sxx; Sxy; Syy; stress-trace)
open import OceanTriton.Expr
open import OceanTriton.Kernels using (tanhE; tanhE-sound)

-- ---------------------------------------------------------------------------------------------
-- The quadruplet transfer as a stencil

private
  ind : Bool → ℚ → ℚ
  ind b x = if b then x else 0ℚ

  eqb-sym : ∀ m k → (m ≡ᵇ k) ≡ (k ≡ᵇ m)
  eqb-sym zero    zero    = refl
  eqb-sym zero    (suc k) = refl
  eqb-sym (suc m) zero    = refl
  eqb-sym (suc m) (suc k) = eqb-sym m k

  -- The gated exchange amount of centre c.
  G : ℕ → (ℕ → ℚ) → ℕ → ℚ
  G n d c = gate (interior? n c) (d c)

  -- No centre at or after n is interior.
  G-out : ∀ n d a → n ℕ.≤ a → G n d a ≡ 0ℚ
  G-out n d a h with interior? n a
  ... | yes (_ , sa<n) = contradiction (ℕP.<-trans (ℕP.n<1+n a) sa<n) (ℕP.≤⇒≯ h)
  ... | no  _          = refl

  -- A sum of an indicator picks one value, also when the index is out of range and the value
  -- is zero there.
  sumTo-pick′ : ∀ n a (w : ℕ → ℚ) → (n ℕ.≤ a → w a ≡ 0ℚ) → sumTo n (pick a w) ≡ w a
  sumTo-pick′ n a w hz with a ℕ.<? n
  ... | yes a<n = sumTo-pick n a w a<n
  ... | no  a≮n =
    trans (sumTo-congr n (pick a w) (λ _ → 0ℚ) off) (trans (sumTo-zero-fn n) (sym (hz (ℕP.≮⇒≥ a≮n))))
    where
    off : ∀ c → c ℕ.< n → pick a w c ≡ 0ℚ
    off c c<n with c ≡ᵇ a in e
    ... | true  = contradiction (Relation.Binary.PropositionalEquality.subst (ℕ._< n) (eqb-true e) c<n) a≮n
    ... | false = refl

  -- One centre's term, split into its three indicators.
  split : ∀ {P : Set} (D : Dec P) x b₁ b₂ b₃ →
    gate D (x * (ind b₁ 1ℚ + ind b₂ 1ℚ - ind b₃ 2ℚ)) ≡ ind b₁ (gate D x) + ind b₂ (gate D x) - ind b₃ (2ℚ * gate D x)
  split (no _)  x true  true  true  = refl
  split (no _)  x true  true  false = refl
  split (no _)  x true  false true  = refl
  split (no _)  x true  false false = refl
  split (no _)  x false true  true  = refl
  split (no _)  x false true  false = refl
  split (no _)  x false false true  = refl
  split (no _)  x false false false = refl
  split (yes _) x true  true  true  = solve 1 (λ x → x :* (con 1ℚ :+ con 1ℚ :- con 2ℚ) := x :+ x :- con 2ℚ :* x) refl x
  split (yes _) x true  true  false = solve 1 (λ x → x :* (con 1ℚ :+ con 1ℚ :- con 0ℚ) := x :+ x :- con 0ℚ) refl x
  split (yes _) x true  false true  = solve 1 (λ x → x :* (con 1ℚ :+ con 0ℚ :- con 2ℚ) := x :+ con 0ℚ :- con 2ℚ :* x) refl x
  split (yes _) x true  false false = solve 1 (λ x → x :* (con 1ℚ :+ con 0ℚ :- con 0ℚ) := x :+ con 0ℚ :- con 0ℚ) refl x
  split (yes _) x false true  true  = solve 1 (λ x → x :* (con 0ℚ :+ con 1ℚ :- con 2ℚ) := con 0ℚ :+ x :- con 2ℚ :* x) refl x
  split (yes _) x false true  false = solve 1 (λ x → x :* (con 0ℚ :+ con 1ℚ :- con 0ℚ) := con 0ℚ :+ x :- con 0ℚ) refl x
  split (yes _) x false false true  = solve 1 (λ x → x :* (con 0ℚ :+ con 0ℚ :- con 2ℚ) := con 0ℚ :+ con 0ℚ :- con 2ℚ :* x) refl x
  split (yes _) x false false false = solve 1 (λ x → x :* (con 0ℚ :+ con 0ℚ :- con 0ℚ) := con 0ℚ :+ con 0ℚ :- con 0ℚ) refl x

  -- The left neighbour's indicator: none at bin 0.
  B : ℕ → ℕ → ℚ → ℚ
  B zero    c x = 0ℚ
  B (suc j) c x = ind (c ≡ᵇ j) x

  turn : ∀ j c x y → ind (suc j ≡ᵇ c) x + ind (j ≡ᵇ suc c) x - ind (j ≡ᵇ c) y
                   ≡ ind (c ≡ᵇ suc j) x + B j c x - ind (c ≡ᵇ j) y
  turn zero c x y =
    cong₂ _-_ (cong₂ _+_ (cong (λ b → ind b x) (eqb-sym 1 c)) refl) (cong (λ b → ind b y) (eqb-sym 0 c))
  turn (suc j) c x y =
    cong₂ _-_ (cong₂ _+_ (cong (λ b → ind b x) (eqb-sym (suc (suc j)) c)) (cong (λ b → ind b x) (eqb-sym j c)))
              (cong (λ b → ind b y) (eqb-sym (suc j) c))

  term : ∀ n d j c → gate (interior? n c) (d c * quad c j)
       ≡ pick (suc j) (G n d) c + B j c (G n d c) - pick j (λ c → 2ℚ * G n d c) c
  term n d j c = trans (split (interior? n c) (d c) (suc j ≡ᵇ c) (j ≡ᵇ suc c) (j ≡ᵇ c))
                       (turn j c (G n d c) (2ℚ * G n d c))

  left-sum : ∀ n d j → sumTo n (λ c → B j c (G n d c)) ≡ gated n d left j
  left-sum n d zero    = sumTo-zero-fn n
  left-sum n d (suc j) = sumTo-pick′ n j (G n d) (G-out n d j)

-- S_nl in bin j is the stencil G(j + 1) + G(j - 1) - 2 G(j) of the gated exchange amounts.
snl-stencil : ∀ n d j → snl n d j ≡ gated n d right j + gated n d left j - 2ℚ * gated n d here j
snl-stencil n d j =
  trans (sumTo-congr n _ _ (λ c _ → term n d j c))
    (trans (sumTo-sub n (λ c → pick (suc j) (G n d) c + B j c (G n d c)) (pick j (λ c → 2ℚ * G n d c)))
      (cong₂ _-_
        (trans (sumTo-add n (pick (suc j) (G n d)) (λ c → B j c (G n d c)))
               (cong₂ _+_ (sumTo-pick′ n (suc j) (G n d) (G-out n d (suc j))) (left-sum n d j)))
        (sumTo-pick′ n j (λ c → 2ℚ * G n d c) (λ h → cong (2ℚ *_) (G-out n d j h)))))

snlE : ∀ {na ns} → Data.Fin.Fin na → Expr na ns
snlE d = gin d right ⊕ gin d left ⊖ con 2ℚ ⊗ gin d here

snlK : Kernel
snlK = record
  { name = "snl" ; na = 1 ; ns = 0
  ; arrays = "d" ∷ [] ; scalars = [] ; shape = map
  ; body = snlE (# 0)
  ; doc = "the quadruplet transfer S_nl (OceanWaves.Sources.snl) as a three-point stencil" }

snlK-sound : ∀ n d j → runMap snlK (sized n (d ∷ []) []) j ≡ snl n d j
snlK-sound n d j = sym (snl-stencil n d j)

-- The stencil kernel keeps the total action, as the sum does.
snlK-conserves : ∀ n d → sumTo n (runMap snlK (sized n (d ∷ []) [])) ≡ 0ℚ
snlK-conserves n d = trans (sumTo-congr n _ _ (λ j _ → snlK-sound n d j)) (snl-conserves-action n d)

-- The source step with S_nl from the exchange amounts d, in one kernel.
sourceSnlK : Kernel
sourceSnlK = record
  { name = "source_step_snl" ; na = 4 ; ns = 2
  ; arrays = "beta" ∷ "gamma" ∷ "N" ∷ "d" ∷ [] ; scalars = "dt" ∷ "L" ∷ [] ; shape = map
  ; body = lin ⊕ max (neg lin) (min (par (# 1)) (par (# 0) ⊗ snlE (# 3)))
  ; doc = "the source step with the limiter and S_nl computed from d (OceanWaves.Sources.sourceStep)" }
  where
  lin : Expr 4 2
  lin = at (# 2) 0 ⊗ (con 1ℚ ⊕ par (# 0) ⊗ at (# 0) 0) ⊘ (con 1ℚ ⊕ par (# 0) ⊗ at (# 1) 0)

sourceSnlK-sound : ∀ Δt L β γ n d N i →
  runMap sourceSnlK (sized n (β ∷ γ ∷ N ∷ d ∷ []) (Δt ∷ L ∷ [])) i ≡ sourceStep Δt L β γ n d N i
sourceSnlK-sound Δt L β γ n d N i =
  cong (λ s → linStep Δt (β i) (γ i) (N i) + limit (linStep Δt (β i) (γ i) (N i)) L (Δt * s))
       (sym (snl-stencil n d i))

-- ---------------------------------------------------------------------------------------------
-- The dispersion solver as a loop kernel

private
  -- The registers are the scalars 0 (lo) and 1 (hi); g and h follow.
  lo hi g h midE : Expr 1 4
  lo = par (# 0)
  hi = par (# 1)
  g  = par (# 2)
  h  = par (# 3)
  midE = (lo ⊕ hi) ⊘ con 2ℚ

  sigma2E : Expr 1 4 → Expr 1 4
  sigma2E x = g ⊗ x ⊗ tanhE (x ⊗ h)

  σσ : Expr 1 4
  σσ = at (# 0) 0 ⊗ at (# 0) 0

wavenumberK : LoopKernel
wavenumberK = record
  { name = "wavenumber" ; na = 1 ; ns = 2
  ; arrays = "sigma" ∷ [] ; scalars = "g" ∷ "h" ∷ []
  ; init = con 0ℚ , max (at (# 0) 0 ⊗ at (# 0) 0 ⊘ par (# 0)) (con (lit 3) ⊘ par (# 1))
  ; step = ifLt (sigma2E midE) σσ midE lo , ifLt (sigma2E midE) σσ hi midE
  ; out  = true
  ; doc  = "the wavenumber of sigma by bisection on [0, kHi0] (OceanWaves.Bisection.waveNumber, Pade tanh)" }

private
  step-eq : ∀ (f : ℚ → ℚ) t k lo hi (D : Dec (f (mid lo hi) Data.Rational.< t)) →
    bisect-step f t k lo hi D ≡ bisect f t k (if does D then mid lo hi else lo) (if does D then hi else mid lo hi)
  step-eq f t k lo hi (yes _) = refl
  step-eq f t k lo hi (no  _) = refl

module _ (W : Medium) (σ : ℕ → ℚ) (i : ℕ) where
  private
    st : Store 1 2
    st = store (σ ∷ []) (Medium.g W ∷ Medium.h W ∷ [])
    f : ℚ → ℚ
    f = sigma2 padeModel W
    t : ℚ
    t = σ i * σ i

    -- One step of the kernel's registers is one step of `bisect`.
    iter-eq : ∀ k a b → iterate (LoopKernel.step wavenumberK) st i k (a , b) ≡ bisect f t k a b
    iter-eq zero    a b = refl
    iter-eq (suc k) a b =
      trans (cong (λ v → iterate (LoopKernel.step wavenumberK) st i k
                           ((if does (v <? t) then mid a b else a) , (if does (v <? t) then b else mid a b)))
                  fm)
            (trans (iter-eq k _ _) (sym (step-eq f t k a b (f (mid a b) <? t))))
      where
      st′ : Store 1 4
      st′ = sized 0 (σ ∷ []) (a ∷ b ∷ Medium.g W ∷ Medium.h W ∷ [])
      fm : eval (sigma2E midE) st′ i ≡ f (mid a b)
      fm = cong (λ u → Medium.g W * mid a b * u) (tanhE-sound (midE ⊗ h) st′ i)

  -- For every number of steps, the kernel gives the wavenumber of `OceanWaves.Bisection`.
  wavenumberK-sound : ∀ iters → runLoop wavenumberK iters st i ≡ waveNumber padeModel W (σ i) iters
  wavenumberK-sound iters = cong proj₂ (iter-eq iters _ _)

-- ---------------------------------------------------------------------------------------------
-- Radiation stress

private
  E n c s : Expr 4 0
  E = at (# 0) 0
  n = at (# 1) 0
  c = at (# 2) 0
  s = at (# 3) 0

sxxK sxyK syyK : Kernel
sxxK = record
  { name = "sxx" ; na = 4 ; ns = 0 ; arrays = "E" ∷ "n" ∷ "cos" ∷ "sin" ∷ [] ; scalars = [] ; shape = map
  ; body = E ⊗ (n ⊗ (con 1ℚ ⊕ c ⊗ c) ⊖ con ½)
  ; doc = "the radiation stress S_xx = E (n (1 + cos^2) - 1/2) (WaveTheory.RadiationStress)" }
sxyK = record
  { name = "sxy" ; na = 4 ; ns = 0 ; arrays = "E" ∷ "n" ∷ "cos" ∷ "sin" ∷ [] ; scalars = [] ; shape = map
  ; body = E ⊗ n ⊗ c ⊗ s
  ; doc = "the radiation stress S_xy = E n cos sin (WaveTheory.RadiationStress)" }
syyK = record
  { name = "syy" ; na = 4 ; ns = 0 ; arrays = "E" ∷ "n" ∷ "cos" ∷ "sin" ∷ [] ; scalars = [] ; shape = map
  ; body = E ⊗ (n ⊗ (con 1ℚ ⊕ s ⊗ s) ⊖ con ½)
  ; doc = "the radiation stress S_yy = E (n (1 + sin^2) - 1/2) (WaveTheory.RadiationStress)" }

stressStore : (E n : ℕ → ℚ) (d : ℕ → Direction) → Store 4 0
stressStore E n d = store (E ∷ n ∷ (λ i → cs (d i)) ∷ (λ i → sn (d i)) ∷ []) []

sxxK-sound : ∀ E n d i → runMap sxxK (stressStore E n d) i ≡ Sxx (E i) (n i) (d i)
sxxK-sound E n d i = refl

sxyK-sound : ∀ E n d i → runMap sxyK (stressStore E n d) i ≡ Sxy (E i) (n i) (d i)
sxyK-sound E n d i = refl

syyK-sound : ∀ E n d i → runMap syyK (stressStore E n d) i ≡ Syy (E i) (n i) (d i)
syyK-sound E n d i = refl

-- The trace of the printed tensor does not depend on the direction.
stressK-trace : ∀ E n d i →
  runMap sxxK (stressStore E n d) i + runMap syyK (stressStore E n d) i ≡ E i * ((1ℚ + 1ℚ + 1ℚ) * n i - 1ℚ)
stressK-trace E n d i = stress-trace (E i) (n i) (d i)

-- The map kernels of this module, and its loop kernel.
stepKernels : List Kernel
stepKernels = snlK L.∷ sourceSnlK L.∷ sxxK L.∷ sxyK L.∷ syyK L.∷ L.[]

loopKernels : List LoopKernel
loopKernels = wavenumberK L.∷ L.[]
