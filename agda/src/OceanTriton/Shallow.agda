{-# OPTIONS --safe --without-K #-}

-- Milestone M3 of ocean-triton/PLAN.md, the kernels of shallow water and of the fractional
-- steps:
--
--   - `snell`, `shoal`, `break_cap`: the map kernels of `WaveTheory.Refraction` (Snell's law on
--     speeds) and `WaveTheory.Shoaling` (the energy flux kept, the depth-limited cap);
--   - `break_scale`: the whole spectrum scaled to the cap, min(1, E_max / m_0) E_i, as one fused
--     launch that first adds m_0 and then writes every bin;
--   - `ds_fused`: the whitecapping rate of `OceanWaves.Sources.dsRate` in one launch, where M0
--     needed three reduce kernels and `ds_rate` (step 4 of M2, moved here);
--   - `strang2d`: Strang splitting of 2-D propagation, half a step in x, a whole step in y,
--     half a step in x, as a program of three launches. y is periodic, so it is also advection
--     in direction θ with one Courant number (WW3 turns refraction into such a step).
--
-- Each one is proved equal to its specification for every input, and the theorems of the
-- specification are restated for its meaning.
module OceanTriton.Shallow where

open import Data.Fin using (#_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _≤_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; subst)

open import OceanWaves.Order using (lit)
open import OceanWaves.Sources using (DsParams; Spectrum; dsRate)
open DsParams using (cDs; delta; alphaPM)
open import WaveTheory.Refraction using (snell; snell-toward-normal)
open import WaveTheory.Shoaling using (shoal; shoal-flux; breakCap; breakCap-le; breakCap-le-max; breakScale; breakScale-le; breakScale-hs)
open import WaveTheory.Propagation2D as P2 using (sweepX; sweepY; total2D; OnGrid; Courant)
import OceanTriton.Expr as E
open E using (Kernel; Store; store; runMap; map)
open import OceanTriton.Gather as G using (KernelG; StoreG; sg; runG)
open import OceanTriton.Grid hiding (nb; np; name; doc; body; na; ns; arrays; scalars)
open import OceanTriton.Space using (sweepXK; sweepYK)

-- ---------------------------------------------------------------------------------------------
-- Map kernels of refraction and shoaling

snellK : Kernel
snellK = record
  { name = "snell" ; na = 3 ; ns = 0 ; arrays = "s" ∷ "c1" ∷ "c2" ∷ [] ; scalars = [] ; shape = map
  ; body = E.at (# 0) 0 E.⊗ E.at (# 2) 0 E.⊘ E.at (# 1) 0
  ; doc = "Snell's law on speeds, sin theta_2 = sin theta_1 c_2 / c_1 (WaveTheory.Refraction.snell)" }

snellK-sound : ∀ s c₁ c₂ i → runMap snellK (store (s ∷ c₁ ∷ c₂ ∷ []) []) i ≡ snell (s i) (c₁ i) (c₂ i)
snellK-sound s c₁ c₂ i = refl

shoalK : Kernel
shoalK = record
  { name = "shoal" ; na = 3 ; ns = 0 ; arrays = "E" ∷ "cg1" ∷ "cg2" ∷ [] ; scalars = [] ; shape = map
  ; body = E.at (# 0) 0 E.⊗ E.at (# 1) 0 E.⊘ E.at (# 2) 0
  ; doc = "shoaling, the energy flux E c_g kept (WaveTheory.Shoaling.shoal)" }

shoalK-sound : ∀ e cg₁ cg₂ i → runMap shoalK (store (e ∷ cg₁ ∷ cg₂ ∷ []) []) i ≡ shoal (e i) (cg₁ i) (cg₂ i)
shoalK-sound e cg₁ cg₂ i = refl

breakCapK : Kernel
breakCapK = record
  { name = "break_cap" ; na = 1 ; ns = 2 ; arrays = "E" ∷ [] ; scalars = "gamma" ∷ "h" ∷ [] ; shape = map
  ; body = E.min (E.at (# 0) 0) (E.par (# 0) E.⊗ E.par (# 0) E.⊗ (E.par (# 1) E.⊗ E.par (# 1)) E.⊘ E.con (lit 16))
  ; doc = "one bin cut to the depth-limited cap (gamma h)^2 / 16 (WaveTheory.Shoaling.breakCap)" }

breakCapK-sound : ∀ γ h e i → runMap breakCapK (store (e ∷ []) (γ ∷ h ∷ [])) i ≡ breakCap γ h (e i)
breakCapK-sound γ h e i = refl

-- The restated theorems: the shoaled energy carries the same flux, and the cap only lowers.
shoalK-flux : ∀ e cg₁ cg₂ i → 0ℚ Data.Rational.< cg₂ i →
  runMap shoalK (store (e ∷ cg₁ ∷ cg₂ ∷ []) []) i Data.Rational.* cg₂ i ≡ e i Data.Rational.* cg₁ i
shoalK-flux e cg₁ cg₂ i = shoal-flux (e i) (cg₁ i)

breakCapK-le : ∀ γ h e i → runMap breakCapK (store (e ∷ []) (γ ∷ h ∷ [])) i ≤ e i
breakCapK-le γ h e i = breakCap-le γ h (e i)

m3Kernels : List Kernel
m3Kernels = snellK ∷ shoalK ∷ breakCapK ∷ []

-- ---------------------------------------------------------------------------------------------
-- Fused kernels

-- Scalars of the body: the sum m0, then gamma and h.
breakScaleK : KernelG
breakScaleK = record
  { name = "break_scale" ; na = 1 ; ni = 0 ; ns = 2 ; nr = 1
  ; arrays = "E" ∷ [] ; idxs = [] ; scalars = "gamma" ∷ "h" ∷ [] ; sums = "m0" ∷ []
  ; reds = G.at (# 0) ∷ []
  ; body = G.min (G.con 1ℚ) (G.par g G.⊗ G.par g G.⊗ (G.par h G.⊗ G.par h) G.⊘ G.con (lit 16) G.⊘ G.par m) G.⊗ G.at (# 0)
  ; doc = "the spectrum scaled to the depth-limited cap, min(1, E_max / m_0) E (WaveTheory.Shoaling.breakScale)" }
  where m = # 0 ; g = # 1 ; h = # 2

breakScaleK-sound : ∀ n γ h σ e i → runG breakScaleK n (sg (e ∷ []) [] (γ ∷ h ∷ [])) i ≡ breakScale n γ h σ e i
breakScaleK-sound n γ h σ e i = refl

-- Every bin stays below its value, and H_s below γ h.
breakScaleK-le : ∀ n γ h σ e → (∀ i → i ℕ.< n → 0ℚ ≤ e i) → ∀ i → i ℕ.< n →
  runG breakScaleK n (sg (e ∷ []) [] (γ ∷ h ∷ [])) i ≤ e i
breakScaleK-le n γ h σ e he = breakScale-le n γ h σ e he

-- Scalars of the body: the sums e_tot, e_sigma, e_k, then c_ds, delta, alpha_pm.
dsFusedK : KernelG
dsFusedK = record
  { name = "ds_fused" ; na = 4 ; ni = 0 ; ns = 3 ; nr = 3
  ; arrays = "sigma" ∷ "N" ∷ "w" ∷ "k" ∷ [] ; idxs = [] ; scalars = "c_ds" ∷ "delta" ∷ "alpha_pm" ∷ []
  ; sums = "e_tot" ∷ "e_sigma" ∷ "e_k" ∷ []
  ; reds = G.at w G.⊗ (G.at σ G.⊗ G.at N)
         ∷ G.at w G.⊗ (G.at σ G.⊗ G.at N) G.⊘ G.at σ
         ∷ G.at w G.⊗ (G.at σ G.⊗ G.at N) G.⊘ G.at k ∷ []
  ; body = G.par cds G.⊗ σm G.⊗ (r G.⊗ r) G.⊗ ((G.con 1ℚ G.⊖ G.par δ) G.⊗ q G.⊕ G.par δ G.⊗ (q G.⊗ q))
  ; doc = "the whitecapping rate with its three sums in one launch (OceanWaves.Sources.dsRate)" }
  where
  σ = # 0 ; N = # 1 ; w = # 2 ; k = # 3
  e = # 0 ; es = # 1 ; ek = # 2 ; cds = # 3 ; δ = # 4 ; α = # 5
  σm km r q : G.ExprG 4 0 6
  σm = G.par e G.⊘ G.par es
  km = G.par e G.⊘ G.par ek
  r  = G.par e G.⊗ (km G.⊗ km) G.⊘ G.par α
  q  = G.at k G.⊘ km

-- The one launch gives the whitecapping rate of every bin.
dsFusedK-sound : ∀ P S i →
  runG dsFusedK (Spectrum.n S) (sg (Spectrum.σ S ∷ Spectrum.N S ∷ Spectrum.w S ∷ Spectrum.k S ∷ []) []
                                  (cDs P ∷ delta P ∷ alphaPM P ∷ [])) i ≡ dsRate P S i
dsFusedK-sound P S i = refl

fusedKernels : List KernelG
fusedKernels = breakScaleK ∷ dsFusedK ∷ []

-- ---------------------------------------------------------------------------------------------
-- Strang splitting in x and θ

strang2D : ℕ → ℕ → ℚ → ℚ → Field → Field
strang2D nx ny cxh cy F = sweepX nx cxh (sweepY ny cy (sweepX nx cxh F))

strangRun : ℕ → ℕ → ℚ → ℚ → ℕ → Field → Field
strangRun nx ny cxh cy zero    F = F
strangRun nx ny cxh cy (suc k) F = strang2D nx ny cxh cy (strangRun nx ny cxh cy k F)

-- Buffers F, T, U; parameters cxh (half the x Courant number) and cy.
strangLaunches : List (Launch 3 2)
strangLaunches =
  launch sweepXK (# 0 ∷ []) (# 0 ∷ []) (# 1) ∷
  launch sweepYK (# 1 ∷ []) (# 1 ∷ []) (# 2) ∷
  launch sweepXK (# 2 ∷ []) (# 0 ∷ []) (# 0) ∷ []

strang : Program
strang = record
  { name = "strang2d" ; nb = 3 ; np = 2 ; buffers = "F" ∷ "T" ∷ "U" ∷ [] ; params = "cxh" ∷ "cy" ∷ []
  ; launches = strangLaunches ; result = # 0
  ; doc = "Strang splitting: half a step in x, a step in y (or theta), half a step in x" }

private
  vec3-eta : ∀ {A : Set} (v : Vec A 3) → v ≡ lookup v (# 0) ∷ lookup v (# 1) ∷ lookup v (# 2) ∷ []
  vec3-eta (a ∷ b ∷ c ∷ []) = refl

strang-run : ∀ nx ny cxh cy k F T U →
  lookup (repeat nx ny (cxh ∷ cy ∷ []) strangLaunches k (F ∷ T ∷ U ∷ [])) (# 0) ≡ strangRun nx ny cxh cy k F
strang-run nx ny cxh cy zero    F T U = refl
strang-run nx ny cxh cy (suc k) F T U =
  trans (cong (λ v → lookup (steps nx ny (cxh ∷ cy ∷ []) strangLaunches v) (# 0)) (vec3-eta r))
        (cong (strang2D nx ny cxh cy) (strang-run nx ny cxh cy k F T U))
  where r = repeat nx ny (cxh ∷ cy ∷ []) strangLaunches k (F ∷ T ∷ U ∷ [])

strang2D-total : ∀ nx ny cxh cy F → total2D nx ny (strang2D (suc nx) (suc ny) cxh cy F) ≡ total2D nx ny F
strang2D-total nx ny cxh cy F =
  trans (P2.sweepX-total nx ny cxh _) (trans (P2.sweepY-total nx ny cy _) (P2.sweepX-total nx ny cxh F))

strangRun-total : ∀ nx ny cxh cy k F → total2D nx ny (strangRun (suc nx) (suc ny) cxh cy k F) ≡ total2D nx ny F
strangRun-total nx ny cxh cy zero    F = refl
strangRun-total nx ny cxh cy (suc k) F =
  trans (strang2D-total nx ny cxh cy _) (strangRun-total nx ny cxh cy k F)

strangRun-nonneg : ∀ nx ny cxh cy → Courant cxh → Courant cy → ∀ k F → OnGrid nx ny (0ℚ ≤_) F →
  OnGrid nx ny (0ℚ ≤_) (strangRun (suc nx) (suc ny) cxh cy k F)
strangRun-nonneg nx ny cxh cy hx hy zero    F hF = hF
strangRun-nonneg nx ny cxh cy hx hy (suc k) F hF =
  P2.sweepX-nonneg nx ny cxh _ hx (P2.sweepY-nonneg nx ny cy _ hy (P2.sweepX-nonneg nx ny cxh _ hx
    (strangRun-nonneg nx ny cxh cy hx hy k F hF)))

-- The theorems, for the program's meaning.
strang-total : ∀ nx ny cxh cy k F T U →
  total2D nx ny (lookup (repeat (suc nx) (suc ny) (cxh ∷ cy ∷ []) strangLaunches k (F ∷ T ∷ U ∷ [])) (# 0)) ≡ total2D nx ny F
strang-total nx ny cxh cy k F T U =
  trans (cong (total2D nx ny) (strang-run (suc nx) (suc ny) cxh cy k F T U)) (strangRun-total nx ny cxh cy k F)

strang-nonneg : ∀ nx ny cxh cy → Courant cxh → Courant cy → ∀ k F T U → OnGrid nx ny (0ℚ ≤_) F →
  OnGrid nx ny (0ℚ ≤_) (lookup (repeat (suc nx) (suc ny) (cxh ∷ cy ∷ []) strangLaunches k (F ∷ T ∷ U ∷ [])) (# 0))
strang-nonneg nx ny cxh cy hx hy k F T U hF =
  subst (OnGrid nx ny (0ℚ ≤_)) (sym (strang-run (suc nx) (suc ny) cxh cy k F T U))
        (strangRun-nonneg nx ny cxh cy hx hy k F hF)
