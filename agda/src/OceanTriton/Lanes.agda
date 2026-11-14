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
--
-- v counts the loop variables in scope and a the accumulators; both are de Bruijn indices,
-- innermost first. Every loop is a left fold in the Fortran's order, so a sum keeps its order.
--
-- A program (`ProgL`) is a list of launches on nf float buffers; each launch runs one body on
-- a lane count and writes one buffer. Its meaning (`runL`) runs them in order. The printer
-- (`OceanTriton.EmitLanes`) is trusted, as every printer here.
module OceanTriton.Lanes where

open import Data.Bool using (Bool; true; false; if_then_else_; _∧_; _∨_; not)
open import Data.Fin using (Fin)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _<ᵇ_)
open import Data.Nat.DivMod using (_/_; _%_)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ)
open import Data.String using (String)
open import Data.Vec as V using (Vec; []; _∷_; lookup; _[_]≔_)

-- Operations, functions and comparisons of float32.
data Op : Set where
  add sub mul div max min : Op

data Fun : Set where
  fsqrt fexp flog ftanh fcos fsin fabs fneg : Fun

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

-- The names of a program: float arrays, integer arrays, float parameters, integer parameters.
record Sig : Set where
  field nf ni nfp nip : ℕ
open Sig

module Syntax (σ : Sig) where

  infixl 6 _+ᵢ_ _∸ᵢ_
  infixl 7 _*ᵢ_

  data IE (v : ℕ) : Set where
    lane : IE v
    var  : Fin v → IE v
    nat  : ℕ → IE v
    ipar : Fin (nip σ) → IE v
    iarr : Fin (ni σ) → IE v → IE v
    _+ᵢ_ _∸ᵢ_ _*ᵢ_ : IE v → IE v → IE v
    quot rem : IE v → IE v → IE v

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

  -- One launch: its body, the integer parameter that is its lane count, and the buffer it writes.
  record Launch : Set where
    constructor launch
    field
      name  : String
      body  : FE 0 0
      lanes : Fin (nip σ)
      out   : Fin (nf σ)
      doc   : String

  record ProgL : Set where
    field
      name     : String
      farrays  : Vec String (nf σ)
      iarrays  : Vec String (ni σ)
      fparams  : Vec String (nfp σ)
      iparams  : Vec String (nip σ)
      launches : List Launch
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

-- What a program reads: its arrays, its parameters.
record Env (σ : Sig) (R : Set) : Set where
  constructor env
  field
    farr : Vec (ℕ → R) (nf σ)
    iarr : Vec (ℕ → ℕ) (ni σ)
    fpar : Vec R (nfp σ)
    ipar : Vec ℕ (nip σ)

module Eval {σ : Sig} {R : Set} (M : Model R) where
  open Syntax σ
  open Model M renaming (op to opM; fun to funM; pow to powM; vpow to vpowM; lit to litM)

  evI : ∀ {v} → Env σ R → ℕ → Vec ℕ v → IE v → ℕ
  evI ρ i ks lane       = i
  evI ρ i ks (var k)    = lookup ks k
  evI ρ i ks (nat n)    = n
  evI ρ i ks (ipar p)   = lookup (Env.ipar ρ) p
  evI ρ i ks (iarr t e) = lookup (Env.iarr ρ) t (evI ρ i ks e)
  evI ρ i ks (p +ᵢ q)   = evI ρ i ks p ℕ.+ evI ρ i ks q
  evI ρ i ks (p ∸ᵢ q)   = evI ρ i ks p ∸ evI ρ i ks q
  evI ρ i ks (p *ᵢ q)   = evI ρ i ks p ℕ.* evI ρ i ks q
  evI ρ i ks (quot p q) = idiv (evI ρ i ks p) (evI ρ i ks q)
  evI ρ i ks (rem p q)  = imod (evI ρ i ks p) (evI ρ i ks q)

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

  -- One launch writes its buffer, every lane at once (the lanes read the buffers as they were).
  stepL : Launch → Env σ R → Env σ R
  stepL L ρ = record ρ { farr = Env.farr ρ [ Launch.out L ]≔ (λ i → evF ρ i [] [] (Launch.body L)) }

  runL : List Launch → Env σ R → Env σ R
  runL []       ρ = ρ
  runL (L ∷ Ls) ρ = runL Ls (stepL L ρ)
