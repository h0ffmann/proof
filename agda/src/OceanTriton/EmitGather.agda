{-# OPTIONS --safe --without-K #-}

-- The Triton printer for the kernels of `OceanTriton.Gather` and their programs. Like
-- `OceanTriton.Emit`, it is trusted: nothing proves that the printed Python means what `evalG`
-- means. Each case is one Triton expression:
--
--     at a          tl.load(a_ptr + i)
--     gat a j       tl.load(a_ptr + tl.load(j_ptr + i))
--     rowW D w      (…((0.0 + w[i D]) + w[i D + 1]) + …), unrolled, in the order of sumTo
--     rowG D w a j  the same with w[i D + k] * a[j[i D + k]]
--     rep e s c R   _rep(e, s, c[i], R): R steps of x = where(t < c, x s, x); it means
--                   repN c[i] only where c[i] ≤ R, which REP_BOUNDS lets the host check
--     the rest      as in `OceanTriton.Emit`
--
-- A kernel with sums is printed as one program: a loop over the lanes for each sum, then a loop
-- that stores every lane. A program prints as a row of PROGRAMS: buffers, index arrays,
-- parameters, lane counts, its launches in order, and the buffers it returns.
module OceanTriton.EmitGather where

open import Data.Fin using (Fin; toℕ)
open import Data.List as L using (List; []; _∷_; concat)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.Product using (_,_; proj₁; proj₂)
open import Data.String using (String; _++_; unlines)
import Data.String
open import Data.Vec as V using (Vec; lookup; toList)

open import OceanTriton.Emit using (pyLit; commas; quoted; tuple)
open import OceanTriton.Gather

module _ {na ni ns} (as : Vec String na) (js : Vec String ni) (ss : Vec String ns) where

  private
    ptr : Fin na → String
    ptr a = lookup as a ++ "_ptr"

    ld : Fin na → String → String
    ld a idx = "tl.load(" ++ ptr a ++ " + " ++ idx ++ ", mask=m, other=0.0)"

    ix : Fin ni → String → String
    ix j at′ = "tl.load(" ++ lookup js j ++ "_ptr + " ++ at′ ++ ", mask=m, other=0)"

    slot : ℕ → ℕ → String
    slot D k = "i * " ++ showℕ D ++ " + " ++ showℕ k

    unroll : ℕ → (ℕ → String) → String
    unroll zero    t = "0.0"
    unroll (suc k) t = "(" ++ unroll k t ++ " + " ++ t k ++ ")"

  pyG : ExprG na ni ns → String
  pyG (at a)         = ld a "i"
  pyG (gat a j)      = ld a (ix j "i")
  pyG (rowW D w)     = unroll D (λ k → ld w (slot D k))
  pyG (rowG D w a j) = unroll D (λ k → "(" ++ ld w (slot D k) ++ " * " ++ ld a (ix j (slot D k)) ++ ")")
  pyG (rep e s c R)  = "_rep(" ++ pyG e ++ ", " ++ lookup ss s ++ ", " ++ ix c "i" ++ ", " ++ showℕ R ++ ")"
  pyG (par s)        = lookup ss s
  pyG (con q)        = pyLit q
  pyG (p ⊕ q)        = "(" ++ pyG p ++ " + " ++ pyG q ++ ")"
  pyG (p ⊖ q)        = "(" ++ pyG p ++ " - " ++ pyG q ++ ")"
  pyG (p ⊗ q)        = "(" ++ pyG p ++ " * " ++ pyG q ++ ")"
  pyG (p ⊘ q)        = "_div0(" ++ pyG p ++ ", " ++ pyG q ++ ")"
  pyG (neg p)        = "(-" ++ pyG p ++ ")"
  pyG (max p q)      = "tl.maximum(" ++ pyG p ++ ", " ++ pyG q ++ ")"
  pyG (min p q)      = "tl.minimum(" ++ pyG p ++ ", " ++ pyG q ++ ")"
  pyG (ifLe x y a b) = "tl.where(" ++ pyG x ++ " <= " ++ pyG y ++ ", " ++ pyG a ++ ", " ++ pyG b ++ ")"

  -- The R of every rep, with the place of its count array among the index arrays, for the host.
  bounds : ExprG na ni ns → List String
  bounds (rep e s c R)  = ("(" ++ showℕ (toℕ c) ++ ", " ++ showℕ R ++ ")") ∷ bounds e
  bounds (p ⊕ q)        = bounds p L.++ bounds q
  bounds (p ⊖ q)        = bounds p L.++ bounds q
  bounds (p ⊗ q)        = bounds p L.++ bounds q
  bounds (p ⊘ q)        = bounds p L.++ bounds q
  bounds (neg p)        = bounds p
  bounds (max p q)      = bounds p L.++ bounds q
  bounds (min p q)      = bounds p L.++ bounds q
  bounds (ifLe x y a b) = bounds x L.++ bounds y L.++ bounds a L.++ bounds b
  bounds _              = []

private
  lane : List String
  lane = "        i = start + tl.arange(0, BLOCK)" ∷ "        m = i < n" ∷ []

  sumLines : ∀ {na ni ns m} → Vec String na → Vec String ni → Vec String ns →
             Vec String m → Vec (ExprG na ni ns) m → List String
  sumLines as js ss V.[] V.[] = []
  sumLines as js ss (s V.∷ sn) (e V.∷ es) =
    ("    acc = tl.zeros([BLOCK], dtype=tl.float32)" ∷
     "    for start in range(0, n, BLOCK):" ∷ lane L.++
     ("        acc += tl.where(m, " ++ pyG as js ss e ++ ", 0.0)") ∷
     ("    " ++ s ++ " = tl.sum(acc, axis=0)") ∷ []) L.++ sumLines as js ss sn es

functionG : KernelG → List String
functionG K with nr K
... | zero =
  "@triton.jit" ∷
  ("def " ++ name K ++ "(" ++ args ++ "):") ∷
  ("    \"\"\"" ++ doc K ++ ".\"\"\"") ∷
  "    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)" ∷
  "    m = i < n" ∷
  ("    tl.store(out_ptr + i, " ++ pyG (arrays K) (idxs K) (V._++_ (sums K) (scalars K)) (body K) ++ ", mask=m)") ∷
  "" ∷ "" ∷ []
  where
  args = commas (L.map (_++ "_ptr") (toList (arrays K)) L.++ L.map (_++ "_ptr") (toList (idxs K))
                 L.++ toList (scalars K) L.++ ("out_ptr" ∷ "n" ∷ "BLOCK: tl.constexpr" ∷ []))
... | suc _ =
  "@triton.jit" ∷
  ("def " ++ name K ++ "(" ++ args ++ "):") ∷
  ("    \"\"\"" ++ doc K ++ "; launch one program.\"\"\"") ∷
  sumLines (arrays K) (idxs K) (scalars K) (sums K) (reds K) L.++
  ("    for start in range(0, n, BLOCK):" ∷ lane L.++
   ("        tl.store(out_ptr + i, " ++ pyG (arrays K) (idxs K) (V._++_ (sums K) (scalars K)) (body K) ++ ", mask=m)") ∷
   "" ∷ "" ∷ [])
  where
  args = commas (L.map (_++ "_ptr") (toList (arrays K)) L.++ L.map (_++ "_ptr") (toList (idxs K))
                 L.++ toList (scalars K) L.++ ("out_ptr" ∷ "n" ∷ "BLOCK: tl.constexpr" ∷ []))

private
  fusedName : KernelG → String
  fusedName K with nr K
  ... | zero  = "False"
  ... | suc _ = "True"

  names : ∀ {n m} → Vec String n → Vec (Fin n) m → String
  names xs is = "(" ++ tuple (toList (V.map (lookup xs) is)) ++ ")"

  launchRow : ∀ {nb nx np nl} → ProgramG → Vec String nb → Vec String nx → Vec String np → Vec String nl →
              LaunchG nb nx np nl → String
  launchRow P bs xs ps ls L =
    "        (" ++ name (kernel L) ++ ", " ++ fusedName (kernel L) ++ ", " ++ names bs (ins L) ++ ", "
    ++ names xs (ixs L) ++ ", " ++ names ps (scs L) ++ ", " ++ quoted (lookup ls (lanes L)) ++ ", "
    ++ quoted (lookup bs (out L)) ++ "),"

programRowsG : ProgramG → List String
programRowsG P =
  ("    " ++ quoted (name P) ++ ": ((" ++ tuple (toList (buffers P)) ++ "), (" ++ tuple (toList (indices P))
     ++ "), (" ++ tuple (toList (params P)) ++ "), (" ++ tuple (toList (sizes P)) ++ "), (") ∷
  L.map (launchRow P (buffers P) (indices P) (params P) (sizes P)) (launches P) L.++
  (("    ), (" ++ Data.String.concat (L.map (λ r → "(" ++ quoted (lookup (buffers P) (proj₁ r)) ++ ", "
                                    ++ quoted (lookup (sizes P) (proj₂ r)) ++ "), ") (results P)) ++ "))," ) ∷ [])

-- A row of KERNELS: whether the kernel is fused (one program) or a map (one lane per lane).
kernelRow : KernelG → String
kernelRow K = "    " ++ quoted (name K) ++ ": (" ++ name K ++ ", " ++ fusedName K ++ "),"

-- The rows of REP_BOUNDS: for a kernel, its count arrays and their bounds.
boundRow : KernelG → List String
boundRow K with bounds (arrays K) (idxs K) (V._++_ (sums K) (scalars K)) (body K)
... | []      = []
... | b ∷ bs = ("    " ++ quoted (name K) ++ ": (" ++ commas (b ∷ bs) ++ ",),") ∷ []

-- The whole Python module.
gatherModule : List KernelG → List ProgramG → String
gatherModule ks ps = unlines (
  "# Generated by tools/ocean-triton/ from agda/src/OceanTriton/ (Gather, Shallow, Mesh, W3SBT1," ∷
  "# W3SNL1). Do not edit: change the Agda and run `just ocean-triton`." ∷
  "\"\"\"The gather kernels and their launch programs (milestones M3 and M4).\"\"\"" ∷
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
  "@triton.jit" ∷
  "def _rep(x, s, c, R: tl.constexpr):" ∷
  "    \"\"\"x s s ... s with c factors, left to right, for c <= R (OceanTriton.Gather.repN).\"\"\"" ∷
  "    for t in tl.static_range(R):" ∷
  "        x = tl.where(t < c, x * s, x)" ∷
  "    return x" ∷
  "" ∷
  "" ∷
  concat (L.map functionG ks) L.++
  ("# name: (kernel, fused): a fused kernel runs as one program, a map kernel one lane per lane" ∷
   "KERNELS = {" ∷ L.map kernelRow ks L.++ ("}" ∷ "" ∷
   "# kernel: ((index array, R), ...): every count a rep reads there must be at most its R" ∷
   "REP_BOUNDS = {" ∷ concat (L.map boundRow ks) L.++ ("}" ∷
   "" ∷
   "# name: (buffers, index arrays, parameters, lane counts," ∷
   "#        launches as (kernel, fused, reads, index arrays, parameters, lanes, writes), results)" ∷
   "PROGRAMS = {" ∷ concat (L.map programRowsG ps) L.++ ("}" ∷ [])))))
