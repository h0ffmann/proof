{-# OPTIONS --safe --without-K #-}

-- Propagation on an unstructured grid, such as a triangle mesh. New: the Lean original has a
-- one-dimensional periodic grid only.
--
-- On a triangle mesh, WAVEWATCH III's explicit unstructured schemes (the PDLIB and UNST
-- switches) keep one action value per node and exchange action between neighbouring nodes
-- through the faces of the median-dual cells. An explicit first-order upwind exchange of that
-- kind has one form for every mesh: in one time step, the cell `src` sends the fraction μ of its
-- content to the cell `dst`, with μ = Δt F / A_src (F the outward flux coefficient of the face,
-- A_src the area of the cell). This module keeps the cell contents M i = A i N i, so no area
-- appears, and the mesh is only a list of directed edges with their fractions.
--
--     M'(i) = (1 - Σ_{e : src e = i} μ e) M(i) + Σ_{e : dst e = i} μ e M(src e)
--
-- For every mesh and every list of edges whose ends are cells of the mesh:
--
-- * the total content is kept exactly, for one step and for k steps (`meshStep-total`,
--   `meshRun-total`);
-- * when the fractions are non-negative and no cell sends more than it has (the CFL condition
--   of an unstructured grid, Σ_out μ ≤ 1 at each cell), the content stays non-negative
--   (`meshStep-nonneg`, `meshRun-nonneg`).
--
-- The edges are not assumed to come in pairs, and the mesh is not assumed to be a
-- triangulation: these two properties need only that every edge moves content from one cell to
-- another. The geometry (which faces, which fluxes) decides only the fractions μ.
module WaveTheory.Unstructured where

open import Data.Bool using (true; false; if_then_else_)
open import Data.List using (List; []; _∷_)
open import Data.Unit using (⊤; tt)
open import Data.Product using (_×_; _,_)
open import Data.Nat as ℕ using (ℕ; zero; suc)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; *-zeroˡ; +-identityʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

open import OceanWaves.Order
open import OceanWaves.Sums

-- One directed edge: the cell that sends, the cell that receives, and the fraction it sends.
record Edge : Set where
  constructor edge
  field
    src dst : ℕ
    μ       : ℚ
open Edge public

-- The fraction that cell i sends in one step, over all its edges.
outRate : List Edge → ℕ → ℚ
outRate []       i = 0ℚ
outRate (e ∷ es) i = pick (src e) (λ _ → μ e) i + outRate es i

-- What cell i receives in one step.
inflow : List Edge → (ℕ → ℚ) → ℕ → ℚ
inflow []       M i = 0ℚ
inflow (e ∷ es) M i = pick (dst e) (λ _ → μ e * M (src e)) i + inflow es M i

-- One explicit step on the mesh.
meshStep : List Edge → (ℕ → ℚ) → ℕ → ℚ
meshStep E M i = (1ℚ - outRate E i) * M i + inflow E M i

-- k steps.
meshRun : List Edge → ℕ → (ℕ → ℚ) → ℕ → ℚ
meshRun E zero    M = M
meshRun E (suc k) M = meshStep E (meshRun E k M)

-- What all the edges move in one step.
moved : List Edge → (ℕ → ℚ) → ℚ
moved []       M = 0ℚ
moved (e ∷ es) M = μ e * M (src e) + moved es M

-- Every edge joins two cells below n.
InMesh : ℕ → List Edge → Set
InMesh n []       = ⊤
InMesh n (e ∷ es) = (src e ℕ.< n) × (dst e ℕ.< n) × InMesh n es

-- ---------------------------------------------------------------------------------------------
-- Conservation

private
  pick-mul : ∀ a (w : ℕ → ℚ) (M : ℕ → ℚ) j → pick a w j * M j ≡ pick a (λ k → w k * M k) j
  pick-mul a w M j with j ℕ.≡ᵇ a
  ... | true  = refl
  ... | false = *-zeroˡ (M j)

-- What the cells send, added over the mesh, is what the edges move.
sent-total : ∀ n E M → InMesh n E → sumTo n (λ i → outRate E i * M i) ≡ moved E M
sent-total n []       M _ = trans (sumTo-congr n _ _ (λ i _ → *-zeroˡ (M i))) (sumTo-zero-fn n)
sent-total n (e ∷ es) M (hs , hd , hes) =
  trans (sumTo-congr n _ _ (λ i _ → step i))
  (trans (sumTo-add n (pick (src e) (λ k → μ e * M k)) (λ i → outRate es i * M i))
         (cong₂ _+_ (sumTo-pick n (src e) (λ k → μ e * M k) hs) (sent-total n es M hes)))
  where
  step : ∀ i → outRate (e ∷ es) i * M i ≡ pick (src e) (λ k → μ e * M k) i + outRate es i * M i
  step i = trans (solve 3 (λ p o m → (p :+ o) :* m := p :* m :+ o :* m) refl
                   (pick (src e) (λ _ → μ e) i) (outRate es i) (M i))
                 (cong (_+ outRate es i * M i) (pick-mul (src e) (λ _ → μ e) M i))

-- What the cells receive, added over the mesh, is also what the edges move.
received-total : ∀ n E M → InMesh n E → sumTo n (inflow E M) ≡ moved E M
received-total n []       M _ = sumTo-zero-fn n
received-total n (e ∷ es) M (hs , hd , hes) =
  trans (sumTo-add n (pick (dst e) (λ _ → μ e * M (src e))) (inflow es M))
        (cong₂ _+_ (sumTo-pick n (dst e) (λ _ → μ e * M (src e)) hd) (received-total n es M hes))

-- One step keeps the total content of the mesh.
meshStep-total : ∀ n E M → InMesh n E → sumTo n (meshStep E M) ≡ sumTo n M
meshStep-total n E M h =
  trans (sumTo-congr n _ _ (λ i _ → split i))
  (trans (sumTo-add n (λ i → M i - outRate E i * M i) (inflow E M))
  (trans (cong (_+ sumTo n (inflow E M)) (sumTo-sub n M (λ i → outRate E i * M i)))
  (trans (cong₂ (λ x y → sumTo n M - x + y) (sent-total n E M h) (received-total n E M h))
         (solve 2 (λ s m → s :- m :+ m := s) refl (sumTo n M) (moved E M)))))
  where
  split : ∀ i → meshStep E M i ≡ (M i - outRate E i * M i) + inflow E M i
  split i = cong (_+ inflow E M i)
              (solve 2 (λ o m → (con 1ℚ :- o) :* m := m :- o :* m) refl (outRate E i) (M i))

meshRun-total : ∀ n E k M → InMesh n E → sumTo n (meshRun E k M) ≡ sumTo n M
meshRun-total n E zero    M h = refl
meshRun-total n E (suc k) M h = trans (meshStep-total n E (meshRun E k M) h) (meshRun-total n E k M h)

-- ---------------------------------------------------------------------------------------------
-- Positivity under the CFL condition

-- Every fraction is non-negative.
NonNegEdges : List Edge → Set
NonNegEdges []       = ⊤
NonNegEdges (e ∷ es) = (0ℚ ≤ μ e) × NonNegEdges es

-- No cell sends more than it holds.
CFLMesh : List Edge → Set
CFLMesh E = ∀ i → outRate E i ≤ 1ℚ

private
  pick-nonneg : ∀ a (w : ℕ → ℚ) j → 0ℚ ≤ w j → 0ℚ ≤ pick a w j
  pick-nonneg a w j hw with j ℕ.≡ᵇ a
  ... | true  = hw
  ... | false = ≤-refl

inflow-nonneg : ∀ E M → NonNegEdges E → (∀ j → 0ℚ ≤ M j) → ∀ i → 0ℚ ≤ inflow E M i
inflow-nonneg []       M _         hM i = ≤-refl
inflow-nonneg (e ∷ es) M (hμ , hes) hM i =
  +-nonneg (pick-nonneg (dst e) (λ _ → μ e * M (src e)) i (*-nonneg hμ (hM (src e))))
           (inflow-nonneg es M hes hM i)

meshStep-nonneg : ∀ E M → NonNegEdges E → CFLMesh E → (∀ j → 0ℚ ≤ M j) → ∀ i → 0ℚ ≤ meshStep E M i
meshStep-nonneg E M hE hC hM i =
  +-nonneg (*-nonneg (≤⇒0≤- (hC i)) (hM i)) (inflow-nonneg E M hE hM i)

meshRun-nonneg : ∀ E k M → NonNegEdges E → CFLMesh E → (∀ j → 0ℚ ≤ M j) → ∀ i → 0ℚ ≤ meshRun E k M i
meshRun-nonneg E zero    M hE hC hM = hM
meshRun-nonneg E (suc k) M hE hC hM = meshStep-nonneg E (meshRun E k M) hE hC (meshRun-nonneg E k M hE hC hM)

-- A cell with no edges keeps its content.
outRate-none : ∀ E i → (∀ M → inflow E M i ≡ 0ℚ) → outRate E i ≡ 0ℚ → ∀ M → meshStep E M i ≡ M i
outRate-none E i hin hout M rewrite hout | hin M =
  solve 1 (λ m → (con 1ℚ :- con 0ℚ) :* m :+ con 0ℚ := m) refl (M i)
