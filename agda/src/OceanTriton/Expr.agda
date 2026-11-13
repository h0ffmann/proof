{-# OPTIONS --safe --without-K #-}

-- A small language for the ocean-wave kernels, so that one Agda term has two readings: an exact
-- meaning over ℚ (`eval`), which the soundness theorems in `OceanTriton.Kernels` prove equal to
-- the kernels of `OceanWaves`, and Triton source (`OceanTriton.Emit`), which runs on a GPU.
--
-- A kernel works on one lane per cell (or per spectral bin) i. Its leaves read the store:
--
--     at a k     the array a at k + i                (a[i + k]); k + i, so that 1 + i is suc i
--     up a s     the array a at i - 1, or the scalar s at i = 0
--                (`upstream` of `OceanWaves.Advection`)
--     par s      the scalar s
--     con q      a rational constant
--
-- The operations are the ones the kernels use: + - * and negation, Lean's total division /₀
-- (x /₀ 0 = 0), max and min (⊔, ⊓), and a choice on x ≤ y.
--
-- A `map` kernel writes one value per lane. A `reduce` kernel writes the sum over the lanes
-- 0 … n - 1, as `sumTo` of `OceanWaves.Sums` does.
module OceanTriton.Expr where

open import Data.Bool using (if_then_else_)
open import Data.Fin using (Fin)
open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Rational using (ℚ; -_; _⊔_; _⊓_; _≤?_)
  renaming (_+_ to _+ℚ_; _-_ to _-ℚ_; _*_ to _*ℚ_)
open import Data.String using (String)
open import Data.Vec using (Vec; lookup)
open import Relation.Nullary using (does)

open import OceanWaves.Order using (_/₀_)
open import OceanWaves.Advection using (upstream)
open import OceanWaves.Sums using (sumTo)

infixl 6 _⊕_ _⊖_
infixl 7 _⊗_ _⊘_

-- An expression over na arrays and ns scalars.
data Expr (na ns : ℕ) : Set where
  at        : Fin na → ℕ → Expr na ns
  up        : Fin na → Fin ns → Expr na ns
  par       : Fin ns → Expr na ns
  con       : ℚ → Expr na ns
  _⊕_ _⊖_ _⊗_ _⊘_ : Expr na ns → Expr na ns → Expr na ns
  neg       : Expr na ns → Expr na ns
  max min   : Expr na ns → Expr na ns → Expr na ns
  ifLe      : Expr na ns → Expr na ns → Expr na ns → Expr na ns → Expr na ns

-- What a kernel reads: na arrays indexed by ℕ and ns scalars.
record Store (na ns : ℕ) : Set where
  constructor store
  field
    arr : Vec (ℕ → ℚ) na
    sc  : Vec ℚ ns
open Store

-- The exact meaning of an expression at lane i.
eval : ∀ {na ns} → Expr na ns → Store na ns → ℕ → ℚ
eval (at a k)       st i = lookup (arr st) a (k + i)
eval (up a s)       st i = upstream (lookup (sc st) s) (lookup (arr st) a) i
eval (par s)        st i = lookup (sc st) s
eval (con q)        st i = q
eval (x ⊕ y)        st i = eval x st i +ℚ eval y st i
eval (x ⊖ y)        st i = eval x st i -ℚ eval y st i
eval (x ⊗ y)        st i = eval x st i *ℚ eval y st i
eval (x ⊘ y)        st i = eval x st i /₀ eval y st i
eval (neg x)        st i = - eval x st i
eval (max x y)      st i = eval x st i ⊔ eval y st i
eval (min x y)      st i = eval x st i ⊓ eval y st i
eval (ifLe x y a b) st i = if does (eval x st i ≤? eval y st i) then eval a st i else eval b st i

data Shape : Set where
  map reduce : Shape

-- A kernel: its name, the names of its arrays and scalars (the arguments of the Triton
-- function, in this order), its shape and its body.
record Kernel : Set where
  field
    name    : String
    na ns   : ℕ
    arrays  : Vec String na
    scalars : Vec String ns
    shape   : Shape
    body    : Expr na ns
    doc     : String
open Kernel public

-- The meaning of a map kernel: the value of lane i.
runMap : (K : Kernel) → Store (na K) (ns K) → ℕ → ℚ
runMap K st i = eval (body K) st i

-- The meaning of a reduce kernel on n lanes.
runReduce : (K : Kernel) → ℕ → Store (na K) (ns K) → ℚ
runReduce K n st = sumTo n (eval (body K) st)
