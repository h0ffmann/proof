{-# OPTIONS --safe --without-K #-}

-- Milestone M3 of ocean-triton/PLAN.md, step 2: propagation on an unstructured grid as a
-- gather, one lane per node.
--
-- `WaveTheory.Unstructured.meshStep` sums over a list of directed edges. A GPU lane cannot
-- walk that list, and a scatter (each edge adds to its target with an atomic) adds in an order
-- that changes from run to run. So the host lays the edges out per node, padded to a fixed
-- width: node i owns the slots i D … i D + D - 1 of each table.
--
--     wout[i D + k]   the fraction of the k-th edge that leaves i, or 0
--     win[i D + k]    the fraction of the k-th edge that enters i, or 0
--     src[i D + k]    the node it comes from, or 0
--
-- and the kernel is M'(i) = (1 - Σ_k wout[i D + k]) M(i) + Σ_k win[i D + k] M(src[i D + k]),
-- each sum in a fixed order. `meshK-sound`: for every edge list whose nodes have at most D
-- edges out and D edges in, it is `meshStep`. `mesh-run`: k launches are `meshRun`, so
-- `meshRun-total` and `meshRun-nonneg` hold for them.
module OceanTriton.Mesh where

open import Data.Bool using (true; false; if_then_else_)
open import Data.Fin using (#_)
open import Data.List as L using (List; []; _∷_; length; foldr)
open import Data.Nat as ℕ using (ℕ; zero; suc; _≤_; _<_; s≤s; z≤n)
import Data.Nat.Properties as ℕP
open import Data.Nat.DivMod using (_/_; _%_; m<n⇒m%n≡m; m<n⇒m/n≡0; [m+kn]%n≡m%n; +-distrib-/-∣ʳ; m*n/n≡m)
open import Data.Nat.Divisibility using (n∣m*n)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _*_)
import Data.Rational as Q
open import Data.Rational.Properties using (+-identityˡ; *-zeroˡ)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.Vec.Relation.Binary.Pointwise.Inductive using (Pointwise; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import OceanWaves.Sums using (sumTo; sumTo-congr; sumTo-succ-left; sumTo-zero-fn; pick)
open import WaveTheory.Unstructured
open import OceanTriton.Gather

-- ---------------------------------------------------------------------------------------------
-- The padded tables

-- The edges that leave i (their fractions), and the edges that enter i (source and fraction).
outs : List Edge → ℕ → List ℚ
outs []       i = []
outs (e ∷ es) i = if i ℕ.≡ᵇ src e then μ e ∷ outs es i else outs es i

inE : List Edge → ℕ → List (ℕ × ℚ)
inE []       i = []
inE (e ∷ es) i = if i ℕ.≡ᵇ dst e then (src e , μ e) ∷ inE es i else inE es i

nthOr : ∀ {A : Set} → List A → ℕ → A → A
nthOr []       k       d = d
nthOr (x ∷ xs) zero    d = x
nthOr (x ∷ xs) (suc k) d = nthOr xs k d

-- A table of rows of width D (= suc D′), row i at i D … i D + D - 1.
flat : ∀ {A : Set} → ℕ → (ℕ → ℕ → A) → ℕ → A
flat D′ f p = f (p / suc D′) (p % suc D′)

flat-at : ∀ {A : Set} D′ (f : ℕ → ℕ → A) i k → k < suc D′ → flat D′ f (i ℕ.* suc D′ ℕ.+ k) ≡ f i k
flat-at D′ f i k hk = cong₂ f quot rem
  where
  D = suc D′
  swap : i ℕ.* D ℕ.+ k ≡ k ℕ.+ i ℕ.* D
  swap = ℕP.+-comm (i ℕ.* D) k
  quot : (i ℕ.* D ℕ.+ k) / D ≡ i
  quot = trans (cong (_/ D) swap)
         (trans (+-distrib-/-∣ʳ k (n∣m*n i))
         (trans (cong₂ ℕ._+_ (m<n⇒m/n≡0 hk) (m*n/n≡m i D)) refl))
  rem : (i ℕ.* D ℕ.+ k) % D ≡ k
  rem = trans (cong (_% D) swap) (trans ([m+kn]%n≡m%n k i D) (m<n⇒m%n≡m hk))

-- The tables of an edge list, with width D′ + 1 out and Di′ + 1 in.
woutT : ℕ → List Edge → ℕ → ℚ
woutT D′ E = flat D′ (λ i k → nthOr (outs E i) k 0ℚ)

winT : ℕ → List Edge → ℕ → ℚ
winT D′ E = flat D′ (λ i k → proj₂ (nthOr (inE E i) k (0 , 0ℚ)))

srcT : ℕ → List Edge → ℕ → ℕ
srcT D′ E = flat D′ (λ i k → proj₁ (nthOr (inE E i) k (0 , 0ℚ)))

-- At most D edges leave and enter every node.
MaxDeg : ℕ → ℕ → List Edge → Set
MaxDeg Do Di E = ∀ i → length (outs E i) ≤ Do × length (inE E i) ≤ Di

-- ---------------------------------------------------------------------------------------------
-- The kernel

meshK : ℕ → ℕ → KernelG
meshK Do′ Di′ = record
  { name = "mesh_step" ; na = 3 ; ni = 1 ; ns = 0 ; nr = 0
  ; arrays = "M" ∷ "wout" ∷ "win" ∷ [] ; idxs = "src" ∷ [] ; scalars = [] ; sums = [] ; reds = []
  ; body = (con 1ℚ ⊖ rowW (suc Do′) (# 1)) ⊗ at (# 0) ⊕ rowG (suc Di′) (# 2) (# 0) (# 0)
  ; doc = "one upwind step on an unstructured grid, a gather over each node's padded edges (WaveTheory.Unstructured.meshStep)" }

meshStore : ℕ → ℕ → List Edge → (ℕ → ℚ) → StoreG 3 1 0
meshStore Do′ Di′ E M = sg (M ∷ woutT Do′ E ∷ winT Di′ E ∷ []) (srcT Di′ E ∷ []) []

private
  -- A padded row sums as its list.
  padded : ∀ {A : Set} (f : A → ℚ) d → f d ≡ 0ℚ → ∀ D (xs : List A) → length xs ≤ D →
    sumTo D (λ k → f (nthOr xs k d)) ≡ foldr (λ a s → f a + s) 0ℚ xs
  padded f d hd D []       _ = trans (sumTo-congr D _ _ (λ k _ → hd)) (sumTo-zero-fn D)
  padded f d hd (suc D) (x ∷ xs) (s≤s h) =
    trans (sumTo-succ-left D _) (cong (f x +_) (padded f d hd D xs h))

  outRate-outs : ∀ E i → outRate E i ≡ foldr (λ a s → a + s) 0ℚ (outs E i)
  outRate-outs []       i = refl
  outRate-outs (e ∷ es) i with i ℕ.≡ᵇ src e
  ... | true  = cong (μ e +_) (outRate-outs es i)
  ... | false = trans (+-identityˡ _) (outRate-outs es i)

  inflow-ins : ∀ E M i → inflow E M i ≡ foldr (λ a s → proj₂ a * M (proj₁ a) + s) 0ℚ (inE E i)
  inflow-ins []       M i = refl
  inflow-ins (e ∷ es) M i with i ℕ.≡ᵇ dst e
  ... | true  = cong (μ e * M (src e) +_) (inflow-ins es M i)
  ... | false = trans (+-identityˡ _) (inflow-ins es M i)

-- The kernel is one step on the mesh, at every node.
meshK-sound : ∀ Do′ Di′ E → MaxDeg (suc Do′) (suc Di′) E → ∀ n M i →
  runG (meshK Do′ Di′) n (meshStore Do′ Di′ E M) i ≡ meshStep E M i
meshK-sound Do′ Di′ E hdeg n M i =
  cong₂ (λ o s → (1ℚ Q.- o) * M i + s) outEq inn
  where
  outEq : sumTo (suc Do′) (λ k → woutT Do′ E (i ℕ.* suc Do′ ℕ.+ k)) ≡ outRate E i
  outEq = trans (sumTo-congr (suc Do′) _ _ (λ k hk → flat-at Do′ (λ i′ k′ → nthOr (outs E i′) k′ 0ℚ) i k hk))
        (trans (padded (λ a → a) 0ℚ refl (suc Do′) (outs E i) (proj₁ (hdeg i))) (sym (outRate-outs E i)))
  inn : sumTo (suc Di′) (λ k → winT Di′ E (i ℕ.* suc Di′ ℕ.+ k) * M (srcT Di′ E (i ℕ.* suc Di′ ℕ.+ k))) ≡ inflow E M i
  inn = trans (sumTo-congr (suc Di′) _ _ (λ k hk → cong₂ (λ w s → w * M s) (flat-at Di′ (λ i′ k′ → proj₂ (nthOr (inE E i′) k′ (0 , 0ℚ))) i k hk) (flat-at Di′ (λ i′ k′ → proj₁ (nthOr (inE E i′) k′ (0 , 0ℚ))) i k hk)))
        (trans (padded (λ a → proj₂ a * M (proj₁ a)) (0 , 0ℚ) (*-zeroˡ (M 0)) (suc Di′) (inE E i) (proj₂ (hdeg i)))
               (sym (inflow-ins E M i)))

-- ---------------------------------------------------------------------------------------------
-- k steps: one launch per step

meshLaunches : ℕ → ℕ → List (LaunchG 3 1 0 1)
meshLaunches Do′ Di′ = launchG (meshK Do′ Di′) (# 0 ∷ # 1 ∷ # 2 ∷ []) (# 0 ∷ []) [] (# 0) (# 0) ∷ []

meshProgram : ℕ → ℕ → ProgramG
meshProgram Do′ Di′ = record
  { name = "mesh" ; nb = 3 ; nx = 1 ; np = 0 ; nl = 1
  ; buffers = "M" ∷ "wout" ∷ "win" ∷ [] ; indices = "src" ∷ [] ; params = [] ; sizes = "nodes" ∷ []
  ; launches = meshLaunches Do′ Di′ ; results = (# 0 , # 0) ∷ []
  ; doc = "k upwind steps on an unstructured grid (WaveTheory.Unstructured.meshRun)" }

module _ (Do′ Di′ : ℕ) (E : List Edge) (n : ℕ) where

  meshRunG : ℕ → (ℕ → ℚ) → Vec (ℕ → ℚ) 3
  meshRunG k M = repeatG (srcT Di′ E ∷ []) [] (n ∷ []) (meshLaunches Do′ Di′) k (M ∷ woutT Do′ E ∷ winT Di′ E ∷ [])

  private
    keep : Vec (ℕ → ℚ) 3 → Vec (ℕ → ℚ) 3
    keep v = lookup v (# 0) ∷ woutT Do′ E ∷ winT Di′ E ∷ []

    run-keep : ∀ k M → meshRunG k M ≡ keep (meshRunG k M)
    run-keep zero    M = refl
    run-keep (suc k) M =
      trans (cong (stepsG (srcT Di′ E ∷ []) [] (n ∷ []) (meshLaunches Do′ Di′)) ih)
            (cong (λ v → keep (stepsG (srcT Di′ E ∷ []) [] (n ∷ []) (meshLaunches Do′ Di′) v)) (sym ih))
      where ih = run-keep k M

  -- k launches are k steps on the mesh.
  mesh-run : MaxDeg (suc Do′) (suc Di′) E → ∀ k M i → lookup (meshRunG k M) (# 0) i ≡ meshRun E k M i
  mesh-run hdeg zero    M i = refl
  mesh-run hdeg (suc k) M i =
    trans (cong (λ v → lookup (stepsG (srcT Di′ E ∷ []) [] (n ∷ []) (meshLaunches Do′ Di′) v) (# 0) i) (run-keep k M))
      (trans (runG-cong (meshK Do′ Di′) n {lookup (meshRunG k M) (# 0) ∷ woutT Do′ E ∷ winT Di′ E ∷ []}
                {meshRun E k M ∷ woutT Do′ E ∷ winT Di′ E ∷ []} (srcT Di′ E ∷ []) []
                (mesh-run hdeg k M ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) i)
             (meshK-sound Do′ Di′ E hdeg n (meshRun E k M) i))

  -- The theorems of Unstructured, for the launches.
  mesh-total : MaxDeg (suc Do′) (suc Di′) E → ∀ m → InMesh m E → ∀ k M →
    sumTo m (lookup (meshRunG k M) (# 0)) ≡ sumTo m M
  mesh-total hdeg m hE k M =
    trans (sumTo-congr m _ _ (λ i _ → mesh-run hdeg k M i)) (meshRun-total m E k M hE)

  mesh-nonneg : MaxDeg (suc Do′) (suc Di′) E → NonNegEdges E → CFLMesh E → ∀ k M → (∀ j → 0ℚ Q.≤ M j) →
    ∀ i → 0ℚ Q.≤ lookup (meshRunG k M) (# 0) i
  mesh-nonneg hdeg hE hC k M hM i =
    subst (0ℚ Q.≤_) (sym (mesh-run hdeg k M i)) (meshRun-nonneg E k M hE hC hM i)
