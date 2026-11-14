{-# OPTIONS --safe --without-K #-}

-- The Triton printer of `OceanTriton.Lanes`. It is trusted: nothing proves that the printed
-- Python means what `evF` means. Each launch is one @triton.jit function with every array and
-- parameter of its program, one lane per thread, and these readings:
--
--     ld x e         tl.load(x_ptr + (e) + z, mask, other=0.0), z = 0 on every lane, so that
--                    an index that does not depend on the lane is still a block
--     iarr t e       the same from an int32 array
--     ∸              tl.maximum(p - q, 0);  quot, rem   //, % (the divisors are NTH or NK)
--     lit q          q as a Python float, rounded to float32 by Triton
--     op             + - * as written, tl.div_rn, tl.maximum, tl.minimum
--     fn             tl.sqrt_rn, tl.exp, tl.log, _tanh, tl.cos, tl.sin, tl.abs, unary -
--     pow x y        _pow(x, y): x * x when y = 2, else exp(y log x) in float64, rounded
--     vpow x y       _vpow(x, y, mv_ptr, z): libmvec's SSE4 powf, lane by lane, from the tables
--                    of ocean-triton/libmvec.py in mv_ptr (every kernel takes it)
--     sel, isel      tl.where (both sides are computed, the one not taken is not read)
--     fold b c e B   r = e; for k in range(b): r = tl.where(k < c, B, r), with the loads of B
--                    masked by k < c; it means foldN only where c ≤ b, which the host checks
--
-- IEEE division and square root are asked for by name (div_rn, sqrt_rn) because Triton's `/`
-- and tl.sqrt are approximate on a GPU; the CPU interpreter computes both exactly either way.
module OceanTriton.EmitLanes where

open import Data.Fin using (Fin)
open import Data.List as L using (List; []; _∷_; _++_)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.String using (String; unlines; intersperse) renaming (_++_ to _⊕_)
import Data.String as S
open import Data.Vec as V using (Vec; []; _∷_; lookup; toList)

open import OceanTriton.Emit using (pyLit)
open import OceanTriton.Lanes

module Print (σ : Sig) (P : Syntax.ProgL σ) where
  open Syntax σ
  open ProgL P

  private
    paren : String → String
    paren s = "(" ⊕ s ⊕ ")"

  pyI : ∀ {v} → Vec String v → String → IE v → String
  pyI ks m lane       = "i"
  pyI ks m (var k)    = lookup ks k
  pyI ks m (nat n)    = showℕ n
  pyI ks m (ipar p)   = lookup iparams p
  pyI ks m (iarr t e) = "tl.load(" ⊕ lookup iarrays t ⊕ "_ptr + " ⊕ paren (pyI ks m e) ⊕ " + z, mask=" ⊕ m ⊕ ", other=0)"
  pyI ks m (p +ᵢ q)   = paren (pyI ks m p ⊕ " + " ⊕ pyI ks m q)
  pyI ks m (p ∸ᵢ q)   = "tl.maximum(" ⊕ pyI ks m p ⊕ " - " ⊕ pyI ks m q ⊕ ", 0)"
  pyI ks m (p *ᵢ q)   = paren (pyI ks m p ⊕ " * " ⊕ pyI ks m q)
  pyI ks m (quot p q) = paren (pyI ks m p ⊕ " // " ⊕ pyI ks m q)
  pyI ks m (rem p q)  = paren (pyI ks m p ⊕ " % " ⊕ pyI ks m q)

  private
    opPy : Op → String → String → String
    opPy add a b = paren (a ⊕ " + " ⊕ b)
    opPy sub a b = paren (a ⊕ " - " ⊕ b)
    opPy mul a b = paren (a ⊕ " * " ⊕ b)
    opPy div a b = "tl.div_rn(" ⊕ a ⊕ ", " ⊕ b ⊕ ")"
    opPy max a b = "tl.maximum(" ⊕ a ⊕ ", " ⊕ b ⊕ ")"
    opPy min a b = "tl.minimum(" ⊕ a ⊕ ", " ⊕ b ⊕ ")"

    funPy : Fun → String → String
    funPy fsqrt a = "tl.sqrt_rn(" ⊕ a ⊕ ")"
    funPy fexp  a = "tl.exp(" ⊕ a ⊕ ")"
    funPy flog  a = "tl.log(" ⊕ a ⊕ ")"
    funPy ftanh a = "_tanh(" ⊕ a ⊕ ")"
    funPy fcos  a = "tl.cos(" ⊕ a ⊕ ")"
    funPy fsin  a = "tl.sin(" ⊕ a ⊕ ")"
    funPy fabs  a = "tl.abs(" ⊕ a ⊕ ")"
    funPy fneg  a = "(-" ⊕ a ⊕ ")"

    cmpPy : Cmp → String
    cmpPy lt = " < "
    cmpPy le = " <= "
    cmpPy ne = " != "

    indent : List String → List String
    indent = L.map ("    " ⊕_)

  -- Statements, the expression, and the next fresh number.
  Out : Set
  Out = List String × String × ℕ

  pyF : ∀ {v a} → Vec String v → Vec String a → String → ℕ → FE v a → Out
  pyF ks rs m c (ld x e) = [] , ("tl.load(" ⊕ lookup farrays x ⊕ "_ptr + " ⊕ paren (pyI ks m e) ⊕ " + z, mask=" ⊕ m ⊕ ", other=0.0)") , c
  pyF ks rs m c (fpar p) = [] , lookup fparams p , c
  pyF ks rs m c (lit q)  = [] , pyLit q , c
  pyF ks rs m c (acc r)  = [] , lookup rs r , c
  pyF ks rs m c (op o p q) with pyF ks rs m c p
  ... | s₁ , e₁ , c₁ with pyF ks rs m c₁ q
  ...   | s₂ , e₂ , c₂ = s₁ ++ s₂ , opPy o e₁ e₂ , c₂
  pyF ks rs m c (fn f p) with pyF ks rs m c p
  ... | s , e , c′ = s , funPy f e , c′
  pyF ks rs m c (pow p q) with pyF ks rs m c p
  ... | s₁ , e₁ , c₁ with pyF ks rs m c₁ q
  ...   | s₂ , e₂ , c₂ = s₁ ++ s₂ , "_pow(" ⊕ e₁ ⊕ ", " ⊕ e₂ ⊕ ")" , c₂
  pyF ks rs m c (vpow p q) with pyF ks rs m c p
  ... | s₁ , e₁ , c₁ with pyF ks rs m c₁ q
  ...   | s₂ , e₂ , c₂ = s₁ ++ s₂ , "_vpow(" ⊕ e₁ ⊕ ", " ⊕ e₂ ⊕ ", mv_ptr, z)" , c₂
  pyF ks rs m c (sel k x y t e) with pyF ks rs m c x
  ... | s₁ , e₁ , c₁ with pyF ks rs m c₁ y
  ...   | s₂ , e₂ , c₂ with pyF ks rs m c₂ t
  ...     | s₃ , e₃ , c₃ with pyF ks rs m c₃ e
  ...       | s₄ , e₄ , c₄ = s₁ ++ s₂ ++ s₃ ++ s₄ , "tl.where(" ⊕ e₁ ⊕ cmpPy k ⊕ e₂ ⊕ ", " ⊕ e₃ ⊕ ", " ⊕ e₄ ⊕ ")" , c₄
  pyF ks rs m c (isel p q t e) with pyF ks rs m c t
  ... | s₃ , e₃ , c₃ with pyF ks rs m c₃ e
  ...   | s₄ , e₄ , c₄ = s₃ ++ s₄ , "tl.where(" ⊕ pyI ks m p ⊕ " < " ⊕ pyI ks m q ⊕ ", " ⊕ e₃ ⊕ ", " ⊕ e₄ ⊕ ")" , c₄
  pyF ks rs m c (fold b n e body) with pyF ks rs m (suc c) e
  ... | s₀ , e₀ , c₀ with pyF (k ∷ ks) (r ∷ rs) m′ c₀ body
    where k = "k" ⊕ showℕ c ; r = "r" ⊕ showℕ c
          m′ = paren (m ⊕ " & (" ⊕ "k" ⊕ showℕ c ⊕ " < " ⊕ pyI ks m n ⊕ ")")
  ...   | s₁ , e₁ , c₁ =
    s₀ ++ (r ⊕ " = " ⊕ e₀ ⊕ " + zf") ∷ ("for " ⊕ k ⊕ " in range(" ⊕ lookup iparams b ⊕ "):") ∷
    indent (s₁ ++ (r ⊕ " = tl.where(" ⊕ k ⊕ " < " ⊕ pyI ks m n ⊕ ", " ⊕ e₁ ⊕ ", " ⊕ r ⊕ ")") ∷ [])
    , r , c₁
    where k = "k" ⊕ showℕ c ; r = "r" ⊕ showℕ c

  args : String
  args = intersperse ", " (L.map (_⊕ "_ptr") (toList farrays) ++ L.map (_⊕ "_ptr") (toList iarrays)
                           ++ toList fparams ++ toList iparams ++ "mv_ptr" ∷ "out_ptr" ∷ "n" ∷ "BLOCK: tl.constexpr" ∷ [])

  kernelPy : Launch → String
  kernelPy L = unlines (
    "@triton.jit" ∷
    ("def " ⊕ Launch.name L ⊕ "(" ⊕ args ⊕ "):") ∷
    ("    \"\"\"" ⊕ Launch.doc L ⊕ "\"\"\"") ∷
    "    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)" ∷
    "    m = i < n" ∷
    "    z = i * 0" ∷
    "    zf = tl.zeros([BLOCK], dtype=tl.float32)" ∷
    indent (proj₁ out) ++
    ("    tl.store(out_ptr + i, " ⊕ proj₁ (proj₂ out) ⊕ " + zf, mask=m)") ∷ [])
    where out = pyF [] [] "m" 0 (Launch.body L)

  private
    q : String → String
    q s = "\"" ⊕ s ⊕ "\""
    tup : List String → String
    tup xs = "(" ⊕ S.concat (L.map (λ x → q x ⊕ ", ") xs) ⊕ ")"

  -- PROGRAMS_L row: arrays, parameters, the launches (function, lane count, buffer written),
  -- the results (buffer, length).
  row : String
  row = "    " ⊕ q name ⊕ ": (" ⊕ tup (toList farrays) ⊕ ", " ⊕ tup (toList iarrays) ⊕ ", "
        ⊕ tup (toList fparams) ⊕ ", " ⊕ tup (toList iparams) ⊕ ",\n        ("
        ⊕ S.concat (L.map (λ L → "(" ⊕ Launch.name L ⊕ ", " ⊕ q (lookup iparams (Launch.lanes L)) ⊕ ", "
                               ⊕ q (lookup farrays (Launch.out L)) ⊕ "), ") launches)
        ⊕ "),\n        (" ⊕ S.concat (L.map (λ r → "(" ⊕ q (lookup farrays (proj₁ r)) ⊕ ", "
                               ⊕ q (lookup iparams (proj₂ r)) ⊕ "), ") results) ⊕ ")),"

  module′ : String
  module′ = S.concat (L.map (λ L → kernelPy L ⊕ "\n\n") launches)

-- A program with its signature, for the module's list.
record AnyProg : Set where
  constructor prog
  field
    sig  : Sig
    body : Syntax.ProgL sig

lanesModule : List AnyProg → String
lanesModule ps = unlines (
  "# Generated by tools/ocean-triton/ from agda/src/OceanTriton/ (Lanes, EmitLanes and the routines" ∷
  "# written in it). Do not edit: change the Agda and run `just ocean-triton`." ∷
  "\"\"\"The lane programs of WAVEWATCH III's ST4 routines and W3SRCE (milestone M4).\"\"\"" ∷
  "" ∷
  "import triton" ∷
  "import triton.language as tl" ∷
  "" ∷
  "import libmvec" ∷
  "" ∷
  "" ∷
  "@triton.jit" ∷
  "def _tanh(x):" ∷
  "    \"\"\"tanh from tl.exp: sign(x) (1 - e) / (1 + e), e = exp(-2 |x|).\"\"\"" ∷
  "    e = tl.exp(-2.0 * tl.abs(x))" ∷
  "    t = tl.div_rn(1.0 - e, 1.0 + e)" ∷
  "    return tl.where(x < 0.0, -t, t)" ∷
  "" ∷
  "" ∷
  "@triton.jit" ∷
  "def _pow(x, y):" ∷
  "    \"\"\"x ** y for x >= 0: x * x when y = 2, else exp(y log x) in float64, rounded once.\"\"\"" ∷
  "    y = tl.where(x == x, y, y)  # a scalar parameter becomes a float32 block" ∷
  "    w = tl.exp(y.to(tl.float64) * tl.log(x.to(tl.float64))).to(tl.float32)" ∷
  "    return tl.where(y == 2.0, x * x, w)" ∷
  "" ∷
  "" ∷
  "_vpow = libmvec.vpowf" ∷
  "" ∷
  "" ∷
  L.map (λ { (prog σ P) → Print.module′ σ P }) ps ++
  "# name: (float arrays, int arrays, float parameters, int parameters, launches, results)" ∷
  "PROGRAMS_L = {" ∷
  L.map (λ { (prog σ P) → Print.row σ P }) ps ++
  "}" ∷ [])
