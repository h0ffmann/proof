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
--     op             + - * as written, tl.div_rn, tl.maximum, tl.minimum, libm.atan2f
--     fn             tl.sqrt_rn, tl.abs, unary -, and glibc's expf, logf, log10f, tanhf, cosf
--                    and sinf as ocean-triton/libm.py writes them, with their bits
--     pow x y        libm.powf, glibc's scalar powf
--     vpow x y       libm.vpowf, one lane of libmvec's SSE4 _ZGVbN4vv_powf
--
-- Every kernel takes lm_ptr, the tables of libm.py, and is launched without contraction.
--     sel, isel      tl.where (both sides are computed, the one not taken is not read)
--     fold b c e B   r = e; for k in range(b): r = tl.where(k < c, B, r), with the loads of B
--                    masked by k < c; it means foldN only where c ≤ b, which the host checks
--
-- IEEE division and square root are asked for by name (div_rn, sqrt_rn) because Triton's `/`
-- and tl.sqrt are approximate on a GPU; the CPU interpreter computes both exactly either way.
module OceanTriton.EmitLanes where

open import Data.Fin using (Fin; zero; suc)
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
  pyI ks m step       = "step"
  pyI ks m (var k)    = lookup ks k
  pyI ks m (nat n)    = showℕ n
  pyI ks m (ipar p)   = lookup iparams p
  pyI ks m (iarr t e) = "tl.load(" ⊕ lookup iarrays t ⊕ "_ptr + " ⊕ paren (pyI ks m e) ⊕ " + z, mask=" ⊕ m ⊕ ", other=0)"
  pyI ks m (p +ᵢ q)   = paren (pyI ks m p ⊕ " + " ⊕ pyI ks m q)
  pyI ks m (p ∸ᵢ q)   = "tl.maximum(" ⊕ pyI ks m p ⊕ " - " ⊕ pyI ks m q ⊕ ", 0)"
  pyI ks m (p *ᵢ q)   = paren (pyI ks m p ⊕ " * " ⊕ pyI ks m q)
  pyI ks m (quot p q) = paren (pyI ks m p ⊕ " // " ⊕ pyI ks m q)
  pyI ks m (rem p q)  = paren (pyI ks m p ⊕ " % " ⊕ pyI ks m q)
  pyI ks m (minᵢ p q) = "tl.minimum(" ⊕ pyI ks m p ⊕ ", " ⊕ pyI ks m q ⊕ ")"
  pyI ks m (maxᵢ p q) = "tl.maximum(" ⊕ pyI ks m p ⊕ ", " ⊕ pyI ks m q ⊕ ")"

  private
    opPy : Op → String → String → String
    opPy add a b = paren (a ⊕ " + " ⊕ b)
    opPy sub a b = paren (a ⊕ " - " ⊕ b)
    opPy mul a b = paren (a ⊕ " * " ⊕ b)
    opPy div a b = "tl.div_rn(" ⊕ a ⊕ ", " ⊕ b ⊕ ")"
    opPy max a b = "tl.maximum(" ⊕ a ⊕ ", " ⊕ b ⊕ ")"
    opPy min a b = "tl.minimum(" ⊕ a ⊕ ", " ⊕ b ⊕ ")"
    opPy atan2 a b = "libm.atan2f(" ⊕ a ⊕ ", " ⊕ b ⊕ ", lm_ptr, z)"

    funPy : Fun → String → String
    funPy fsqrt a = "tl.sqrt_rn(" ⊕ a ⊕ ")"
    funPy fexp  a = "libm.expf(" ⊕ a ⊕ ", lm_ptr, z)"
    funPy flog  a = "libm.logf(" ⊕ a ⊕ ", lm_ptr, z)"
    funPy flog10 a = "libm.log10f(" ⊕ a ⊕ ", lm_ptr, z)"
    funPy ftanh a = "libm.tanhf(" ⊕ a ⊕ ", lm_ptr, z)"
    funPy fcos  a = "libm.cosf(" ⊕ a ⊕ ", lm_ptr, z)"
    funPy fsin  a = "libm.sinf(" ⊕ a ⊕ ", lm_ptr, z)"
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
  ...   | s₂ , e₂ , c₂ = s₁ ++ s₂ , "libm.powf(" ⊕ e₁ ⊕ ", " ⊕ e₂ ⊕ ", lm_ptr, z)" , c₂
  pyF ks rs m c (vpow p q) with pyF ks rs m c p
  ... | s₁ , e₁ , c₁ with pyF ks rs m c₁ q
  ...   | s₂ , e₂ , c₂ = s₁ ++ s₂ , "libm.vpowf(" ⊕ e₁ ⊕ ", " ⊕ e₂ ⊕ ", lm_ptr, z)" , c₂
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

  pyF ks rs m c (fold2 w b n e₁ e₂ b₁ b₂) with pyF ks rs m (suc c) e₁
  ... | s₀ , x₀ , c₀ with pyF ks rs m c₀ e₂
  ...   | s₀′ , y₀ , c₀′ with pyF (k ∷ ks) (r ∷ r′ ∷ rs) m′ c₀′ b₁
    where k = "k" ⊕ showℕ c ; r = "r" ⊕ showℕ c ; r′ = "q" ⊕ showℕ c
          m′ = paren (m ⊕ " & (" ⊕ "k" ⊕ showℕ c ⊕ " < " ⊕ pyI ks m n ⊕ ")")
  ...     | s₁ , x₁ , c₁ with pyF (k ∷ ks) (r ∷ r′ ∷ rs) m′ c₁ b₂
    where k = "k" ⊕ showℕ c ; r = "r" ⊕ showℕ c ; r′ = "q" ⊕ showℕ c
          m′ = paren (m ⊕ " & (" ⊕ "k" ⊕ showℕ c ⊕ " < " ⊕ pyI ks m n ⊕ ")")
  ...       | s₂ , y₁ , c₂ =
    s₀ ++ s₀′ ++ (r ⊕ " = " ⊕ x₀ ⊕ " + zf") ∷ (r′ ⊕ " = " ⊕ y₀ ⊕ " + zf") ∷ ("for " ⊕ k ⊕ " in range(" ⊕ lookup iparams b ⊕ "):") ∷
    indent (s₁ ++ s₂ ++ ("n" ⊕ r ⊕ " = " ⊕ x₁) ∷ ("n" ⊕ r′ ⊕ " = " ⊕ y₁)
            ∷ (r ⊕ " = tl.where(" ⊕ k ⊕ " < " ⊕ pyI ks m n ⊕ ", n" ⊕ r ⊕ ", " ⊕ r ⊕ ")")
            ∷ (r′ ⊕ " = tl.where(" ⊕ k ⊕ " < " ⊕ pyI ks m n ⊕ ", n" ⊕ r′ ⊕ ", " ⊕ r′ ⊕ ")") ∷ [])
    , pickS w r r′ , c₂
    where k = "k" ⊕ showℕ c ; r = "r" ⊕ showℕ c ; r′ = "q" ⊕ showℕ c
          pickS : Fin 2 → String → String → String
          pickS zero    a _ = a
          pickS (suc _) _ b = b
  pyF ks rs m c (bind e body) with pyF ks rs m (suc c) e
  ... | s₀ , e₀ , c₀ with pyF ks (r ∷ rs) m c₀ body
    where r = "b" ⊕ showℕ c
  ...   | s₁ , e₁ , c₁ = s₀ ++ (r ⊕ " = " ⊕ e₀ ⊕ " + zf") ∷ s₁ , e₁ , c₁
    where r = "b" ⊕ showℕ c
  pyF ks rs m c (ix e body) with pyF ks rs m (suc c) e
  ... | s₀ , e₀ , c₀ with pyF (k ∷ ks) rs m c₀ body
    where k = "j" ⊕ showℕ c
  ...   | s₁ , e₁ , c₁ = s₀ ++ (k ⊕ " = tl.maximum((" ⊕ e₀ ⊕ " + zf).to(tl.int32), 0)") ∷ s₁ , e₁ , c₁
    where k = "j" ⊕ showℕ c
  pyF ks rs m c (real e) = [] , "((" ⊕ pyI ks m e ⊕ ") + z).to(tl.float32)" , c

  args : String
  args = intersperse ", " (L.map (_⊕ "_ptr") (toList farrays) ++ L.map (_⊕ "_ptr") (toList iarrays)
                           ++ toList fparams ++ toList iparams ++ "step" ∷ "lm_ptr" ∷ "out_ptr" ∷ "n" ∷ "BLOCK: tl.constexpr" ∷ [])

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

  private
    triple : Launch → String
    triple L = "(" ⊕ Launch.name L ⊕ ", " ⊕ q (lookup iparams (Launch.lanes L)) ⊕ ", "
               ⊕ q (lookup farrays (Launch.out L)) ⊕ "), "
    item : Item → String
    item (single L)  = triple L
    item (loop c Ls) = "(\"loop\", " ⊕ q (lookup iparams c) ⊕ ", (" ⊕ S.concat (L.map triple Ls) ⊕ ")), "
    kernels : Item → List Launch
    kernels (single L)  = L ∷ []
    kernels (loop c Ls) = Ls


  -- PROGRAMS_L row: arrays, parameters, the launches (function, lane count, buffer written;
  -- a loop is ("loop", count, launches)), the results (buffer, length).
  row : String
  row = "    " ⊕ q name ⊕ ": (" ⊕ tup (toList farrays) ⊕ ", " ⊕ tup (toList iarrays) ⊕ ", "
        ⊕ tup (toList fparams) ⊕ ", " ⊕ tup (toList iparams) ⊕ ",\n        ("
        ⊕ S.concat (L.map item launches)
        ⊕ "),\n        (" ⊕ S.concat (L.map (λ r → "(" ⊕ q (lookup farrays (proj₁ r)) ⊕ ", "
                               ⊕ q (lookup iparams (proj₂ r)) ⊕ "), ") results) ⊕ ")),"

  module′ : String
  module′ = S.concat (L.map (λ L → kernelPy L ⊕ "\n\n") (L.concatMap kernels launches))

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
  "import libm" ∷
  "" ∷
  "" ∷
  L.map (λ { (prog σ P) → Print.module′ σ P }) ps ++
  "# name: (float arrays, int arrays, float parameters, int parameters, launches, results)" ∷
  "PROGRAMS_L = {" ∷
  L.map (λ { (prog σ P) → Print.row σ P }) ps ++
  "}" ∷ [])
