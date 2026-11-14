{-# OPTIONS --safe --without-K #-}

-- The Triton printer: each kernel of `OceanTriton.Kernels` as a `@triton.jit` function, one
-- program per block of BLOCK lanes. This file is the trusted part of the chain: nothing proves
-- that the printed Python means what `eval` means. It is kept small so that a reader can check
-- it case by case against `eval` in `OceanTriton.Expr`:
--
--     at a k      tl.load(a_ptr + i + k, mask=m, other=0.0)
--     up a s      tl.where(i > 0, a[i - 1], s)
--     par s       the scalar argument s
--     con (p/q)   the float literal p.0 / q.0
--     + - * neg   the same operators on float32
--     /₀          _div0(x, y): x / y, and 0 where y = 0 (Lean's total division)
--     ⊔ ⊓         tl.maximum, tl.minimum
--     ifLe, ifLt  tl.where(x <= y, a, b), tl.where(x < y, a, b)
--     gin a o     a[c] where 1 <= c and c + 1 < n, else 0, for c = i - 1, i, i + 1
--
-- A map kernel stores lane i of out for i < n. A reduce kernel adds the lanes 0 … n - 1 in one
-- program and stores the sum in out[0]. Triton adds in another order than `sumTo` and rounds;
-- the exact sum is the same.
module OceanTriton.Emit where

open import Data.Fin using (Fin)
open import Data.Integer using (ℤ; +_; -[1+_])
open import Data.Integer.Show using () renaming (show to showℤ)
open import Data.List as L using (List; []; _∷_; concat)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.Rational using (ℚ; ↥_; ↧ₙ_)
open import Data.String using (String; _++_; unlines; intersperse)
open import Data.Vec using (Vec; lookup; toList; _∷_)
open import Data.Bool using (if_then_else_)
open import Data.Product using (proj₁; proj₂)

open import OceanTriton.Expr

-- A rational constant as a Python float expression.
pyLit : ℚ → String
pyLit q with ↧ₙ q
... | 1 = "(" ++ showℤ (↥ q) ++ ".0)"
... | d = "(" ++ showℤ (↥ q) ++ ".0 / " ++ showℕ d ++ ".0)"

module _ {na ns} (as : Vec String na) (ss : Vec String ns) where

  ptr : Fin na → String
  ptr a = lookup as a ++ "_ptr"

  offset : ℕ → String
  offset zero = "i"
  offset k    = "i + " ++ showℕ k

  py : Expr na ns → String
  py (at a k)       = "tl.load(" ++ ptr a ++ " + " ++ offset k ++ ", mask=m, other=0.0)"
  py (up a s)       = "tl.where(i > 0, tl.load(" ++ ptr a ++ " + i - 1, mask=m & (i > 0), other=0.0), "
                      ++ lookup ss s ++ ")"
  py (par s)        = lookup ss s
  py (con q)        = pyLit q
  py (x ⊕ y)        = "(" ++ py x ++ " + " ++ py y ++ ")"
  py (x ⊖ y)        = "(" ++ py x ++ " - " ++ py y ++ ")"
  py (x ⊗ y)        = "(" ++ py x ++ " * " ++ py y ++ ")"
  py (x ⊘ y)        = "_div0(" ++ py x ++ ", " ++ py y ++ ")"
  py (neg x)        = "(-" ++ py x ++ ")"
  py (max x y)      = "tl.maximum(" ++ py x ++ ", " ++ py y ++ ")"
  py (min x y)      = "tl.minimum(" ++ py x ++ ", " ++ py y ++ ")"
  py (ifLe x y a b) = "tl.where(" ++ py x ++ " <= " ++ py y ++ ", " ++ py a ++ ", " ++ py b ++ ")"
  py (ifLt x y a b) = "tl.where(" ++ py x ++ " < " ++ py y ++ ", " ++ py a ++ ", " ++ py b ++ ")"
  py (gin a left)   = "tl.where((i >= 2) & (i < n), tl.load(" ++ ptr a ++ " + i - 1, mask=m & (i >= 2), other=0.0), 0.0)"
  py (gin a here)   = "tl.where((i >= 1) & (i + 1 < n), tl.load(" ++ ptr a ++ " + i, mask=m, other=0.0), 0.0)"
  py (gin a right)  = "tl.where(i + 2 < n, tl.load(" ++ ptr a ++ " + i + 1, mask=m & (i + 2 < n), other=0.0), 0.0)"

commas : List String → String
commas = intersperse ", "

quoted : String → String
quoted s = "\"" ++ s ++ "\""

-- The arguments of the Triton function: the arrays, the scalars, out, n and BLOCK.
params : Kernel → String
params K = commas (L.map (_++ "_ptr") (toList (arrays K)) L.++ toList (scalars K)
                   L.++ ("out_ptr" ∷ "n" ∷ "BLOCK: tl.constexpr" ∷ []))

function : Kernel → List String
function K with shape K
... | map =
  "@triton.jit" ∷
  ("def " ++ name K ++ "(" ++ params K ++ "):") ∷
  ("    \"\"\"" ++ doc K ++ ".\"\"\"") ∷
  "    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)" ∷
  "    m = i < n" ∷
  ("    tl.store(out_ptr + i, " ++ py (arrays K) (scalars K) (body K) ++ ", mask=m)") ∷
  "" ∷ "" ∷ []
... | reduce =
  "@triton.jit" ∷
  ("def " ++ name K ++ "(" ++ params K ++ "):") ∷
  ("    \"\"\"" ++ doc K ++ "; launch one program.\"\"\"") ∷
  "    acc = tl.zeros([BLOCK], dtype=tl.float32)" ∷
  "    for start in range(0, n, BLOCK):" ∷
  "        i = start + tl.arange(0, BLOCK)" ∷
  "        m = i < n" ∷
  ("        acc += tl.where(m, " ++ py (arrays K) (scalars K) (body K) ++ ", 0.0)") ∷
  "    tl.store(out_ptr, tl.sum(acc, axis=0))" ∷
  "" ∷ "" ∷ []

shapeName : Shape → String
shapeName map    = "map"
shapeName reduce = "reduce"

-- A loop kernel: the registers r0 and r1 as tensors of BLOCK lanes, `iters` steps, then the
-- register `out`.
loopFunction : LoopKernel → List String
loopFunction K =
  "@triton.jit" ∷
  ("def " ++ LoopKernel.name K ++ "(" ++ ps ++ "):") ∷
  ("    \"\"\"" ++ LoopKernel.doc K ++ ".\"\"\"") ∷
  "    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)" ∷
  "    m = i < n" ∷
  ("    r0 = tl.zeros([BLOCK], dtype=tl.float32) + " ++ py as ss (proj₁ (LoopKernel.init K))) ∷
  ("    r1 = tl.zeros([BLOCK], dtype=tl.float32) + " ++ py as ss (proj₂ (LoopKernel.init K))) ∷
  "    for _ in range(iters):" ∷
  ("        s0 = " ++ py as rs (proj₁ (LoopKernel.step K))) ∷
  ("        s1 = " ++ py as rs (proj₂ (LoopKernel.step K))) ∷
  "        r0 = s0" ∷
  "        r1 = s1" ∷
  ("    tl.store(out_ptr + i, " ++ (if LoopKernel.out K then "r1" else "r0") ++ ", mask=m)") ∷
  "" ∷ "" ∷ []
  where
  as = LoopKernel.arrays K
  ss = LoopKernel.scalars K
  rs = "r0" ∷ "r1" ∷ ss
  ps = commas (L.map (_++ "_ptr") (toList as) L.++ toList ss
               L.++ ("out_ptr" ∷ "n" ∷ "iters" ∷ "BLOCK: tl.constexpr" ∷ []))

tuple : List String → String
tuple xs = Data.String.concat (L.map (λ x → quoted x ++ ", ") xs)

loopRow : LoopKernel → String
loopRow K = "    " ++ quoted (LoopKernel.name K) ++ ": (" ++ LoopKernel.name K ++ ", \"loop\", ("
        ++ tuple (toList (LoopKernel.arrays K)) ++ "), (" ++ tuple (toList (LoopKernel.scalars K)) ++ ")),"

-- One row of the KERNELS table: the function, its shape, its arrays and its scalars.
row : Kernel → String
row K = "    " ++ quoted (name K) ++ ": (" ++ name K ++ ", " ++ quoted (shapeName (shape K)) ++ ", ("
        ++ tuple (toList (arrays K)) ++ "), (" ++ tuple (toList (scalars K)) ++ ")),"

-- The whole Python module.
module′ : List Kernel → List LoopKernel → String
module′ ks ls = unlines (
  "# Generated by tools/ocean-triton/ from agda/src/OceanTriton/Kernels.agda. Do not edit:" ∷
  "# change the Agda and run `just ocean-triton`." ∷
  "\"\"\"The ocean-wave kernels of agda/src/OceanWaves/ as Triton kernels.\"\"\"" ∷
  "" ∷
  "import triton" ∷
  "import triton.language as tl" ∷
  "" ∷
  "" ∷
  "@triton.jit" ∷
  "def _div0(x, y):" ∷
  "    \"\"\"x / y, and 0 where y = 0 (the total division of OceanWaves.Order).\"\"\"" ∷
  "    nz = y != 0.0" ∷
  "    return tl.where(nz, x / tl.where(nz, y, 1.0), 0.0)" ∷
  "" ∷
  "" ∷
  concat (L.map function ks) L.++ concat (L.map loopFunction ls) L.++
  ("# name: (function, shape, arrays, scalars)" ∷
   "KERNELS = {" ∷ L.map row ks L.++ L.map loopRow ls L.++ ("}" ∷ [])))
