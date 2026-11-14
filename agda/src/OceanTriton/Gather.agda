{-# OPTIONS --safe --without-K #-}

-- Kernels that read through index arrays, and programs of their launches (milestones M3 and
-- M4 of ocean-triton/PLAN.md).
--
-- WAVEWATCH III reads its spectrum through tables: the DIA of W3SNL1 reads each quadruplet's
-- four neighbours through index arrays that INSNL1 fills, and an unstructured grid reads each
-- node's neighbours through an edge list. `ExprG` adds these reads to the leaves of
-- `OceanTriton.Expr`:
--
--     at a          a[i]
--     gat a j       a[j[i]], j an index array
--     rowW D w      w[i D] + … + w[i D + D - 1], in that order
--     rowG D w a j  the same sum of w[i D + k] a[j[i D + k]]: one row of a padded edge list
--     rep e s c R   e s s … s with c[i] factors s, multiplied left to right; the printed loop
--                   runs R times, so it means this only where c[i] ≤ R (the host checks it)
--
-- A kernel may also start with reductions: its scalars are then its sums over the n lanes,
-- then its own scalars. Printed, it is one program that first adds each sum and then writes
-- every lane (a fused kernel): one launch where the M0 kernels needed one per sum and one more.
module OceanTriton.Gather where

open import Data.Bool using (if_then_else_; true; false)
open import Data.Fin using (Fin)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc)
open import Data.Product using (_×_)
open import Data.Rational using (ℚ; 0ℚ; -_; _⊔_; _⊓_; _≤?_)
  renaming (_+_ to _+ℚ_; _-_ to _-ℚ_; _*_ to _*ℚ_)
open import Data.String using (String)
open import Data.Vec as V using (Vec; lookup; _[_]≔_; _++_)
open import Data.Vec.Relation.Binary.Pointwise.Inductive as PW using (Pointwise)
open import Relation.Binary.PropositionalEquality using (_≡_; _≗_; refl; cong; cong₂)
open import Relation.Nullary using (does)

open import OceanWaves.Order using (_/₀_)
open import OceanWaves.Sums using (sumTo; sumTo-congr)

infixl 6 _⊕_ _⊖_
infixl 7 _⊗_ _⊘_

data ExprG (na ni ns : ℕ) : Set where
  at    : Fin na → ExprG na ni ns
  gat   : Fin na → Fin ni → ExprG na ni ns
  rowW  : ℕ → Fin na → ExprG na ni ns
  rowG  : ℕ → Fin na → Fin na → Fin ni → ExprG na ni ns
  rep   : ExprG na ni ns → Fin ns → Fin ni → ℕ → ExprG na ni ns
  par   : Fin ns → ExprG na ni ns
  con   : ℚ → ExprG na ni ns
  _⊕_ _⊖_ _⊗_ _⊘_ : ExprG na ni ns → ExprG na ni ns → ExprG na ni ns
  neg   : ExprG na ni ns → ExprG na ni ns
  max min : ExprG na ni ns → ExprG na ni ns → ExprG na ni ns
  ifLe  : ExprG na ni ns → ExprG na ni ns → ExprG na ni ns → ExprG na ni ns → ExprG na ni ns

record StoreG (na ni ns : ℕ) : Set where
  constructor sg
  field
    arr : Vec (ℕ → ℚ) na
    idx : Vec (ℕ → ℕ) ni
    sc  : Vec ℚ ns
open StoreG

-- x s s … s with m factors, multiplied left to right.
repN : ℕ → ℚ → ℚ → ℚ
repN zero    s x = x
repN (suc m) s x = repN m s x *ℚ s

evalG : ∀ {na ni ns} → ExprG na ni ns → StoreG na ni ns → ℕ → ℚ
evalG (at a)         st i = lookup (arr st) a i
evalG (gat a j)      st i = lookup (arr st) a (lookup (idx st) j i)
evalG (rowW D w)     st i = sumTo D (λ k → lookup (arr st) w (i ℕ.* D ℕ.+ k))
evalG (rowG D w a j) st i =
  sumTo D (λ k → lookup (arr st) w (i ℕ.* D ℕ.+ k) *ℚ lookup (arr st) a (lookup (idx st) j (i ℕ.* D ℕ.+ k)))
evalG (rep e s c R)  st i = repN (lookup (idx st) c i) (lookup (sc st) s) (evalG e st i)
evalG (par s)        st i = lookup (sc st) s
evalG (con q)        st i = q
evalG (p ⊕ q)        st i = evalG p st i +ℚ evalG q st i
evalG (p ⊖ q)        st i = evalG p st i -ℚ evalG q st i
evalG (p ⊗ q)        st i = evalG p st i *ℚ evalG q st i
evalG (p ⊘ q)        st i = evalG p st i /₀ evalG q st i
evalG (neg p)        st i = - evalG p st i
evalG (max p q)      st i = evalG p st i ⊔ evalG q st i
evalG (min p q)      st i = evalG p st i ⊓ evalG q st i
evalG (ifLe x y a b) st i = if does (evalG x st i ≤? evalG y st i) then evalG a st i else evalG b st i

-- The value of an expression depends on the arrays only through their values.
evalG-cong : ∀ {na ni ns} (e : ExprG na ni ns) {as bs : Vec (ℕ → ℚ) na} (ix : Vec (ℕ → ℕ) ni) (s : Vec ℚ ns) →
  Pointwise _≗_ as bs → ∀ i → evalG e (sg as ix s) i ≡ evalG e (sg bs ix s) i
evalG-cong (at a)         ix s h i = PW.lookup h a i
evalG-cong (gat a j)      ix s h i = PW.lookup h a (lookup ix j i)
evalG-cong (rowW D w)     ix s h i = sumTo-congr D _ _ (λ k _ → PW.lookup h w (i ℕ.* D ℕ.+ k))
evalG-cong (rowG D w a j) ix s h i =
  sumTo-congr D _ _ (λ k _ → cong₂ _*ℚ_ (PW.lookup h w (i ℕ.* D ℕ.+ k)) (PW.lookup h a (lookup ix j (i ℕ.* D ℕ.+ k))))
evalG-cong (rep e c n R)  ix s h i = cong (repN (lookup ix n i) (lookup s c)) (evalG-cong e ix s h i)
evalG-cong (par _)        ix s h i = refl
evalG-cong (con _)        ix s h i = refl
evalG-cong (p ⊕ q)        ix s h i = cong₂ _+ℚ_ (evalG-cong p ix s h i) (evalG-cong q ix s h i)
evalG-cong (p ⊖ q)        ix s h i = cong₂ _-ℚ_ (evalG-cong p ix s h i) (evalG-cong q ix s h i)
evalG-cong (p ⊗ q)        ix s h i = cong₂ _*ℚ_ (evalG-cong p ix s h i) (evalG-cong q ix s h i)
evalG-cong (p ⊘ q)        ix s h i = cong₂ _/₀_ (evalG-cong p ix s h i) (evalG-cong q ix s h i)
evalG-cong (neg p)        ix s h i = cong -_ (evalG-cong p ix s h i)
evalG-cong (max p q)      ix s h i = cong₂ _⊔_ (evalG-cong p ix s h i) (evalG-cong q ix s h i)
evalG-cong (min p q)      ix s h i = cong₂ _⊓_ (evalG-cong p ix s h i) (evalG-cong q ix s h i)
evalG-cong (ifLe x y a b) ix s h i
  rewrite evalG-cong x ix s h i | evalG-cong y ix s h i | evalG-cong a ix s h i | evalG-cong b ix s h i = refl

-- A kernel: arrays, index arrays, scalars, and nr sums over the lanes, which come first in the
-- body's scalars. With nr = 0 it is a map kernel.
record KernelG : Set where
  field
    name    : String
    na ni ns nr : ℕ
    arrays  : Vec String na
    idxs    : Vec String ni
    scalars : Vec String ns
    sums    : Vec String nr
    reds    : Vec (ExprG na ni ns) nr
    body    : ExprG na ni (nr ℕ.+ ns)
    doc     : String
open KernelG public

-- The meaning of a kernel run on n lanes: the value of lane i.
runG : (K : KernelG) → ℕ → StoreG (na K) (ni K) (ns K) → ℕ → ℚ
runG K n st i = evalG (body K) (sg (arr st) (idx st) (V.map (λ e → sumTo n (evalG e st)) (reds K) ++ sc st)) i

-- The same congruence for a whole kernel.
runG-cong : ∀ K n {as bs} ix s → Pointwise _≗_ as bs → ∀ i → runG K n (sg as ix s) i ≡ runG K n (sg bs ix s) i
runG-cong K n {as} {bs} ix s h i =
  trans′ (evalG-cong (body K) ix _ h i) (cong (λ v → evalG (body K) (sg bs ix (v ++ s)) i) (sums-eq (reds K)))
  where
  open import Relation.Binary.PropositionalEquality using () renaming (trans to trans′)
  sums-eq : ∀ {m} (es : Vec (ExprG (na K) (ni K) (ns K)) m) →
    V.map (λ e → sumTo n (evalG e (sg as ix s))) es ≡ V.map (λ e → sumTo n (evalG e (sg bs ix s))) es
  sums-eq V.[]       = refl
  sums-eq (e V.∷ es) = cong₂ V._∷_ (sumTo-congr n _ _ (λ k _ → evalG-cong e ix s h k)) (sums-eq es)

-- ---------------------------------------------------------------------------------------------
-- Programs

-- One launch on nb buffers, with nx index arrays, np parameters and nl lane counts.
record LaunchG (nb nx np nl : ℕ) : Set where
  constructor launchG
  field
    kernel : KernelG
    ins    : Vec (Fin nb) (na kernel)
    ixs    : Vec (Fin nx) (ni kernel)
    scs    : Vec (Fin np) (ns kernel)
    lanes  : Fin nl
    out    : Fin nb
open LaunchG public

record ProgramG : Set where
  field
    name     : String
    nb nx np nl : ℕ
    buffers  : Vec String nb
    indices  : Vec String nx
    params   : Vec String np
    sizes    : Vec String nl
    launches : List (LaunchG nb nx np nl)
    results  : List (Fin nb × Fin nl)
    doc      : String
open ProgramG public

module _ {nb nx np nl : ℕ} (ix : Vec (ℕ → ℕ) nx) (ps : Vec ℚ np) (ls : Vec ℕ nl) where

  stepG : LaunchG nb nx np nl → Vec (ℕ → ℚ) nb → Vec (ℕ → ℚ) nb
  stepG L bs = bs [ out L ]≔ runG (kernel L) (lookup ls (lanes L))
    (sg (V.map (lookup bs) (ins L)) (V.map (lookup ix) (ixs L)) (V.map (lookup ps) (scs L)))

  stepsG : List (LaunchG nb nx np nl) → Vec (ℕ → ℚ) nb → Vec (ℕ → ℚ) nb
  stepsG []       bs = bs
  stepsG (L ∷ Ls) bs = stepsG Ls (stepG L bs)

  repeatG : List (LaunchG nb nx np nl) → ℕ → Vec (ℕ → ℚ) nb → Vec (ℕ → ℚ) nb
  repeatG Ls zero    bs = bs
  repeatG Ls (suc k) bs = stepsG Ls (repeatG Ls k bs)
