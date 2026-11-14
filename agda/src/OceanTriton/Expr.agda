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
--     gin a o    the array a at bin i - 1, i or i + 1 (o = left, here, right) when that bin is
--                interior (1 ≤ c and c + 1 < n), else 0: the gated exchange amounts of the
--                quadruplet transfer (`gate (interior? n c)` of `OceanWaves.Sources`)
--
-- The operations are the ones the kernels use: + - * and negation, Lean's total division /₀
-- (x /₀ 0 = 0), max and min (⊔, ⊓), and a choice on x ≤ y or on x < y.
--
-- A `map` kernel writes one value per lane. A `reduce` kernel writes the sum over the lanes
-- 0 … n - 1, as `sumTo` of `OceanWaves.Sums` does.
module OceanTriton.Expr where

open import Data.Bool using (Bool; if_then_else_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Fin using (Fin)
open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Rational using (ℚ; 0ℚ; -_; _⊔_; _⊓_; _≤?_; _<?_)
  renaming (_+_ to _+ℚ_; _-_ to _-ℚ_; _*_ to _*ℚ_)
open import Data.String using (String)
open import Data.Vec using (Vec; lookup; _∷_)
open import Relation.Nullary using (does)

open import OceanWaves.Order using (_/₀_)
open import OceanWaves.Advection using (upstream)
open import OceanWaves.Sums using (sumTo)
open import OceanWaves.Sources using (gate; interior?)

-- Which neighbour a gated read takes.
data Off : Set where
  left here right : Off

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
  ifLe ifLt : Expr na ns → Expr na ns → Expr na ns → Expr na ns → Expr na ns
  gin       : Fin na → Off → Expr na ns

-- What a kernel reads: na arrays indexed by ℕ, ns scalars, and the number of lanes n (only the
-- gated reads use it).
record Store (na ns : ℕ) : Set where
  constructor sized
  field
    size : ℕ
    arr  : Vec (ℕ → ℚ) na
    sc   : Vec ℚ ns
open Store

-- A store for kernels with no gated read.
store : ∀ {na ns} → Vec (ℕ → ℚ) na → Vec ℚ ns → Store na ns
store = sized 0

-- The gated read: a c when the bin c = i - 1, i or i + 1 is interior, else 0.
gated : ℕ → (ℕ → ℚ) → Off → ℕ → ℚ
gated n a left  zero    = 0ℚ
gated n a left  (suc i) = gate (interior? n i) (a i)
gated n a here  i       = gate (interior? n i) (a i)
gated n a right i       = gate (interior? n (suc i)) (a (suc i))

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
eval (ifLt x y a b) st i = if does (eval x st i <? eval y st i) then eval a st i else eval b st i
eval (gin a o)      st i = gated (size st) (lookup (arr st) a) o i

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

-- A loop kernel: two registers per lane, set by `init`, then `iters` times replaced by `step`,
-- whose expressions read the registers as the scalars 0 and 1 (the kernel's own scalars follow
-- them). The lane writes register `out`. This is the shape of a bisection.
record LoopKernel : Set where
  field
    name    : String
    na ns   : ℕ
    arrays  : Vec String na
    scalars : Vec String ns
    init    : Expr na ns × Expr na ns
    step    : Expr na (2 + ns) × Expr na (2 + ns)
    out     : Bool
    doc     : String

-- k steps from the registers (r₀, r₁), first step first, as `bisect` recurses.
iterate : ∀ {na ns} → Expr na (2 + ns) × Expr na (2 + ns) → Store na ns → ℕ → ℕ → ℚ × ℚ → ℚ × ℚ
iterate stp st i zero    r = r
iterate stp st i (suc k) (r₀ , r₁) =
  iterate stp st i k (eval (proj₁ stp) st′ i , eval (proj₂ stp) st′ i)
  where st′ = sized (Store.size st) (Store.arr st) (r₀ ∷ r₁ ∷ Store.sc st)

-- The register a lane writes.
select : Bool → ℚ × ℚ → ℚ
select b r = if b then proj₂ r else proj₁ r

runLoop : (K : LoopKernel) → ℕ → Store (LoopKernel.na K) (LoopKernel.ns K) → ℕ → ℚ
runLoop K k st i =
  select (LoopKernel.out K)
    (iterate (LoopKernel.step K) st i k
       (eval (proj₁ (LoopKernel.init K)) st i , eval (proj₂ (LoopKernel.init K)) st i))
