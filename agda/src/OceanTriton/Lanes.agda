{-# OPTIONS --safe --without-K #-}

-- The kernel language of WAVEWATCH III's ST4 routines and of W3SRCE (milestone M4): one lane
-- per spectral point or per bin, float32 arithmetic over a `Model`, index arithmetic on ℕ, and
-- loops written as the Fortran writes them.
--
-- ST4 needs what `OceanTriton.Gather` cannot say: SQRT, EXP, LOG, TANH, COS, SIN and real
-- powers (so ℚ cannot be the arithmetic), indices computed from the lane (IS0 = (IK-1) NTH),
-- integer tables (SATINDICES), reductions whose length depends on the lane (the cumulative term
-- sums the bins up to IK - DIKCUMUL), and conditions on integers and on floats inside a loop.
--
--     IE v      an index: the lane, a loop variable, a literal, an integer parameter, an integer
--               array read, + ∸ * and quotient and remainder (by zero they give 0)
--     FE v a    a float: an array read at an index, a parameter, a literal, an accumulator, an
--               operation, a function, a power, a choice on floats or on indices, and
--     fold b c e body
--               r := e; for k = 0 … c - 1: r := body (k, r); the value is r. b is the integer
--               parameter that bounds c, for the printer (Triton's loop needs a scalar bound,
--               and the host checks c ≤ b on every lane).
--     fold2 w b c e₁ e₂ b₁ b₂
--               the same with two accumulators updated together (W3SIN4's stress sums along
--               x and y); w picks the one that is the value
--     bind e body
--               let: e is computed once and is accumulator 0 in body
--     ix e body
--               INT(e) (truncation toward zero, 0 below 0) is loop variable 0 in body, for an
--               index read from a float (W3SIN4's table indices)
--     real i    REAL(i), an index as a float
--
-- IE also has min and max. v counts the loop variables in scope and a the accumulators; both are de Bruijn indices,
-- innermost first. Every loop is a left fold in the Fortran's order, so a sum keeps its order.
--
-- A program (`ProgL`) is a list of launches on nf float buffers, some of them in loops; each
-- launch runs one body on a lane count and writes one buffer. Its meaning (`runL`) runs them in
-- order, a loop's body once per step. The printer
-- (`OceanTriton.EmitLanes`) is trusted, as every printer here.
module OceanTriton.Lanes where

open import Data.Bool using (Bool; true; false; if_then_else_; _∧_; _∨_; not)
open import Data.Fin using (Fin; zero; suc)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _<ᵇ_)
open import Data.Nat.DivMod using (_/_; _%_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ)
open import Data.String using (String)
open import Data.Vec as V using (Vec; []; _∷_; lookup; _[_]≔_)
import Data.Vec.Properties as VP
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; cong)

-- Operations, functions and comparisons of float32.
data Op : Set where
  add sub mul div max min atan2 : Op

data Fun : Set where
  fsqrt fexp flog flog10 ftanh fcos fsin fabs fneg : Fun

data Cmp : Set where
  lt le ne : Cmp

-- The arithmetic: any type with these. `lit` reads a decimal literal of the Fortran, as the
-- compiler rounds it.
record Model (R : Set) : Set where
  field
    op  : Op → R → R → R
    fun : Fun → R → R
    pow : R → R → R
    -- x ** y as one lane of glibc's libmvec _ZGVbN4vv_powf computes it: gfortran -O3 sends a
    -- loop of real powers there four lanes at a time, and libmvec and powf differ by a few ULP.
    vpow : R → R → R
    lit : ℚ → R
    cmp : Cmp → R → R → Bool
    -- REAL(n) and INT(x) for a table's index: INT truncates toward zero, and every index of
    -- the routines here is clamped at 0 or above, so a negative or NaN x may give 0.
    fromℕ : ℕ → R
    trunc : R → ℕ

-- The names of a program: float arrays, integer arrays, float parameters, integer parameters.
record Sig : Set where
  field nf ni nfp nip : ℕ
open Sig

module Syntax (σ : Sig) where

  infixl 6 _+ᵢ_ _∸ᵢ_
  infixl 7 _*ᵢ_

  data IE (v : ℕ) : Set where
    lane : IE v
    step : IE v                          -- the step of the loop the launch runs in (0 outside one)
    var  : Fin v → IE v
    nat  : ℕ → IE v
    ipar : Fin (nip σ) → IE v
    iarr : Fin (ni σ) → IE v → IE v
    _+ᵢ_ _∸ᵢ_ _*ᵢ_ : IE v → IE v → IE v
    quot rem minᵢ maxᵢ : IE v → IE v → IE v

  data FE (v a : ℕ) : Set where
    ld   : Fin (nf σ) → IE v → FE v a
    fpar : Fin (nfp σ) → FE v a
    lit  : ℚ → FE v a
    acc  : Fin a → FE v a
    op   : Op → FE v a → FE v a → FE v a
    fn   : Fun → FE v a → FE v a
    pow  : FE v a → FE v a → FE v a
    vpow : FE v a → FE v a → FE v a
    sel  : Cmp → FE v a → FE v a → FE v a → FE v a → FE v a   -- if x cmp y then t else e
    isel : IE v → IE v → FE v a → FE v a → FE v a              -- if p < q then t else e
    fold : Fin (nip σ) → IE v → FE v a → FE (suc v) (suc a) → FE v a
    -- Two accumulators that read each other (W3SIN4's stress, x and y): both start, both step
    -- from the pair before, and the Fin 2 says which one is the value. acc 0 is the first.
    fold2 : Fin 2 → Fin (nip σ) → IE v → FE v a → FE v a →
            FE (suc v) (suc (suc a)) → FE (suc v) (suc (suc a)) → FE v a
    bind : FE v a → FE v (suc a) → FE v a                      -- let acc 0 = e in body
    ix   : FE v a → FE (suc v) a → FE v a                      -- let var 0 = INT(e) in body
    real : IE v → FE v a                                       -- REAL of an index

  -- Renaming, to move a term under a binder: `wk` for one more accumulator, `wkI` for one more
  -- loop variable.
  private
    lift : ∀ {m n} → (Fin m → Fin n) → Fin (suc m) → Fin (suc n)
    lift f zero    = zero
    lift f (suc i) = suc (f i)

  renI : ∀ {v w} → (Fin v → Fin w) → IE v → IE w
  renI f lane       = lane
  renI f step       = step
  renI f (var k)    = var (f k)
  renI f (nat n)    = nat n
  renI f (ipar p)   = ipar p
  renI f (iarr t e) = iarr t (renI f e)
  renI f (p +ᵢ q)   = renI f p +ᵢ renI f q
  renI f (p ∸ᵢ q)   = renI f p ∸ᵢ renI f q
  renI f (p *ᵢ q)   = renI f p *ᵢ renI f q
  renI f (quot p q) = quot (renI f p) (renI f q)
  renI f (rem p q)  = rem (renI f p) (renI f q)
  renI f (minᵢ p q) = minᵢ (renI f p) (renI f q)
  renI f (maxᵢ p q) = maxᵢ (renI f p) (renI f q)

  ren : ∀ {v w a b} → (Fin v → Fin w) → (Fin a → Fin b) → FE v a → FE w b
  ren f g (ld x e)        = ld x (renI f e)
  ren f g (fpar p)        = fpar p
  ren f g (lit q)         = lit q
  ren f g (acc r)         = acc (g r)
  ren f g (op o p q)      = op o (ren f g p) (ren f g q)
  ren f g (fn h p)        = fn h (ren f g p)
  ren f g (pow p q)       = pow (ren f g p) (ren f g q)
  ren f g (vpow p q)      = vpow (ren f g p) (ren f g q)
  ren f g (sel c x y t e) = sel c (ren f g x) (ren f g y) (ren f g t) (ren f g e)
  ren f g (isel p q t e)  = isel (renI f p) (renI f q) (ren f g t) (ren f g e)
  ren f g (fold b c e body) = fold b (renI f c) (ren f g e) (ren (lift f) (lift g) body)
  ren f g (fold2 w b c e₁ e₂ b₁ b₂) =
    fold2 w b (renI f c) (ren f g e₁) (ren f g e₂) (ren (lift f) (lift (lift g)) b₁) (ren (lift f) (lift (lift g)) b₂)
  ren f g (bind e body)   = bind (ren f g e) (ren f (lift g) body)
  ren f g (ix e body)     = ix (ren f g e) (ren (lift f) g body)
  ren f g (real e)        = real (renI f e)

  wk : ∀ {v a} → FE v a → FE v (suc a)
  wk = ren (λ k → k) suc

  wkI : ∀ {v} → IE v → IE (suc v)
  wkI = renI suc

  wkV : ∀ {v a} → FE v a → FE (suc v) a
  wkV = ren suc (λ r → r)

  -- One launch: its body, the integer parameter that is its lane count, and the buffer it writes.
  record Launch : Set where
    constructor launch
    field
      name  : String
      body  : FE 0 0
      lanes : Fin (nip σ)
      out   : Fin (nf σ)
      doc   : String

  -- What a program runs: a launch, or launches repeated for step = 0 … c - 1, c an integer
  -- parameter. A DO loop whose iterations depend on each other (W3SIN4's sheltering, band after
  -- band; W3SRCE's time steps) is a loop of launches, each writing what the next step reads.
  data Item : Set where
    single : Launch → Item
    loop : Fin (nip σ) → List Launch → Item

  record ProgL : Set where
    field
      name     : String
      farrays  : Vec String (nf σ)
      iarrays  : Vec String (ni σ)
      fparams  : Vec String (nfp σ)
      iparams  : Vec String (nip σ)
      launches : List Item
      results  : List (Fin (nf σ) × Fin (nip σ))   -- a buffer and its length
      doc      : String

-- Quotient and remainder, total: by zero they give zero.
idiv imod : ℕ → ℕ → ℕ
idiv m zero    = 0
idiv m (suc n) = m / suc n
imod m zero    = 0
imod m (suc n) = m % suc n

-- The left fold of the Fortran's DO loop: k = 0 … c - 1.
foldN : ∀ {R : Set} → ℕ → R → (ℕ → R → R) → R
foldN zero    r f = r
foldN (suc c) r f = f c (foldN c r f)

pick : ∀ {R : Set} → Fin 2 → R × R → R
pick zero    p = proj₁ p
pick (suc _) p = proj₂ p

-- What a program reads: its arrays, its parameters.
record Env (σ : Sig) (R : Set) : Set where
  constructor env
  field
    farr : Vec (ℕ → R) (nf σ)
    iarr : Vec (ℕ → ℕ) (ni σ)
    fpar : Vec R (nfp σ)
    ipar : Vec ℕ (nip σ)
    stp  : ℕ

module Eval {σ : Sig} {R : Set} (M : Model R) where
  open Syntax σ
  open Model M renaming (op to opM; fun to funM; pow to powM; vpow to vpowM; lit to litM; fromℕ to fromℕM)

  evI : ∀ {v} → Env σ R → ℕ → Vec ℕ v → IE v → ℕ
  evI ρ i ks lane       = i
  evI ρ i ks step       = Env.stp ρ
  evI ρ i ks (var k)    = lookup ks k
  evI ρ i ks (nat n)    = n
  evI ρ i ks (ipar p)   = lookup (Env.ipar ρ) p
  evI ρ i ks (iarr t e) = lookup (Env.iarr ρ) t (evI ρ i ks e)
  evI ρ i ks (p +ᵢ q)   = evI ρ i ks p ℕ.+ evI ρ i ks q
  evI ρ i ks (p ∸ᵢ q)   = evI ρ i ks p ∸ evI ρ i ks q
  evI ρ i ks (p *ᵢ q)   = evI ρ i ks p ℕ.* evI ρ i ks q
  evI ρ i ks (quot p q) = idiv (evI ρ i ks p) (evI ρ i ks q)
  evI ρ i ks (rem p q)  = imod (evI ρ i ks p) (evI ρ i ks q)
  evI ρ i ks (minᵢ p q) = evI ρ i ks p ℕ.⊓ evI ρ i ks q
  evI ρ i ks (maxᵢ p q) = evI ρ i ks p ℕ.⊔ evI ρ i ks q

  evF : ∀ {v a} → Env σ R → ℕ → Vec ℕ v → Vec R a → FE v a → R
  evF ρ i ks rs (ld x e)         = lookup (Env.farr ρ) x (evI ρ i ks e)
  evF ρ i ks rs (fpar p)         = lookup (Env.fpar ρ) p
  evF ρ i ks rs (lit q)          = litM q
  evF ρ i ks rs (acc r)          = lookup rs r
  evF ρ i ks rs (op o p q)       = opM o (evF ρ i ks rs p) (evF ρ i ks rs q)
  evF ρ i ks rs (fn f p)         = funM f (evF ρ i ks rs p)
  evF ρ i ks rs (pow p q)        = powM (evF ρ i ks rs p) (evF ρ i ks rs q)
  evF ρ i ks rs (vpow p q)       = vpowM (evF ρ i ks rs p) (evF ρ i ks rs q)
  evF ρ i ks rs (sel c x y t e)  = if cmp c (evF ρ i ks rs x) (evF ρ i ks rs y) then evF ρ i ks rs t else evF ρ i ks rs e
  evF ρ i ks rs (isel p q t e)   = if evI ρ i ks p <ᵇ evI ρ i ks q then evF ρ i ks rs t else evF ρ i ks rs e
  evF ρ i ks rs (fold b c e body) =
    foldN (evI ρ i ks c) (evF ρ i ks rs e) (λ k r → evF ρ i (k ∷ ks) (r ∷ rs) body)
  evF ρ i ks rs (fold2 w b c e₁ e₂ b₁ b₂) =
    pick w (foldN (evI ρ i ks c) (evF ρ i ks rs e₁ , evF ρ i ks rs e₂)
              (λ k p → evF ρ i (k ∷ ks) (proj₁ p ∷ proj₂ p ∷ rs) b₁ , evF ρ i (k ∷ ks) (proj₁ p ∷ proj₂ p ∷ rs) b₂))
  evF ρ i ks rs (bind e body)    = evF ρ i ks (evF ρ i ks rs e ∷ rs) body
  evF ρ i ks rs (ix e body)      = evF ρ i (trunc (evF ρ i ks rs e) ∷ ks) rs body
  evF ρ i ks rs (real e)         = fromℕM (evI ρ i ks e)

  -- One launch writes its buffer, every lane at once (the lanes read the buffers as they were).
  stepL : Launch → Env σ R → Env σ R
  stepL L ρ = record ρ { farr = Env.farr ρ [ Launch.out L ]≔ (λ i → evF ρ i [] [] (Launch.body L)) }

  -- What a launch leaves in a buffer, proved for any launch: a proof that reads a buffer through
  -- these never makes Agda evaluate a body to compare two environments.
  stepL-here : ∀ L ρ i → lookup (Env.farr (stepL L ρ)) (Launch.out L) i ≡ evF ρ i [] [] (Launch.body L)
  stepL-here L ρ i = cong (λ f → f i) (VP.lookup∘update (Launch.out L) (Env.farr ρ) _)

  stepL-other : ∀ L ρ b i → b ≢ Launch.out L → lookup (Env.farr (stepL L ρ)) b i ≡ lookup (Env.farr ρ) b i
  stepL-other L ρ b i b≢ = cong (λ f → f i) (VP.lookup∘update′ b≢ (Env.farr ρ) _)

  runLs : List Launch → Env σ R → Env σ R
  runLs []       ρ = ρ
  runLs (L ∷ Ls) ρ = runLs Ls (stepL L ρ)

  runL : List Item → Env σ R → Env σ R
  runL []                ρ = ρ
  runL (single L ∷ Is)   ρ = runL Is (stepL L ρ)
  runL (loop c Ls ∷ Is)  ρ = runL Is (foldN (lookup (Env.ipar ρ) c) ρ (λ k ρ′ → runLs Ls (record ρ′ { stp = k })))
