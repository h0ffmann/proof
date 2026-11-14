{-# OPTIONS --safe --without-K #-}

-- Kernels on a 2-D field and programs of kernel launches (milestone M2 of ocean-triton/PLAN.md).
--
-- A 2-D kernel has one lane per cell (x, y) of an nx × ny field, `Field = ℕ → ℕ → ℚ`. Its leaves:
--
--     cell a      a at (x, y)
--     west a      a at (x - 1, y), and a at (nx - 1, y) for x = 0 (periodic in x)
--     south a     a at (x, y - 1), and a at (x, ny - 1) for y = 0 (periodic in y)
--     giny a o    a at (x, c) for c = y - 1, y, y + 1 when 1 ≤ c and c + 1 < ny, else 0: the
--                 gated read of `OceanTriton.Expr` along y, where y is a spectral bin
--
-- The two periodic reads are the upstream values of `OceanWaves.Advection.advectPeriodic`, so a
-- sweep in x or in y is the 1-D kernel in every row or column.
--
-- A program is a list of launches on nb buffers: each launch runs one kernel on some buffers and
-- writes one buffer. Its meaning runs the launches in order. A host script that launches the
-- printed kernels in the same order computes that meaning, up to float32; the soundness
-- theorems of `OceanTriton.Space` say that it is the model's time step.
module OceanTriton.Grid where

open import Data.Fin using (Fin)
open import Data.List using (List; []; _∷_)
open import Data.Nat using (ℕ; zero; suc; _∸_)
open import Data.Rational using (ℚ; -_; _⊔_; _⊓_)
  renaming (_+_ to _+ℚ_; _-_ to _-ℚ_; _*_ to _*ℚ_)
open import Data.String using (String)
open import Data.Vec using (Vec; lookup; map; _[_]≔_)

open import OceanWaves.Order using (_/₀_)
open import OceanWaves.Advection using (upstream)
open import OceanTriton.Expr using (Off; left; here; right; gated) public

infixl 6 _⊕_ _⊖_
infixl 7 _⊗_ _⊘_

Field : Set
Field = ℕ → ℕ → ℚ

data Expr2 (na ns : ℕ) : Set where
  cell west south : Fin na → Expr2 na ns
  giny      : Fin na → Off → Expr2 na ns
  par       : Fin ns → Expr2 na ns
  con       : ℚ → Expr2 na ns
  _⊕_ _⊖_ _⊗_ _⊘_ : Expr2 na ns → Expr2 na ns → Expr2 na ns
  neg       : Expr2 na ns → Expr2 na ns
  max min   : Expr2 na ns → Expr2 na ns → Expr2 na ns

record Store2 (na ns : ℕ) : Set where
  constructor store2
  field
    nx ny : ℕ
    arr   : Vec Field na
    sc    : Vec ℚ ns
open Store2

eval2 : ∀ {na ns} → Expr2 na ns → Store2 na ns → ℕ → ℕ → ℚ
eval2 (cell a)   st x y = lookup (arr st) a x y
eval2 (west a)   st x y = upstream (lookup (arr st) a (nx st ∸ 1) y) (λ x′ → lookup (arr st) a x′ y) x
eval2 (south a)  st x y = upstream (lookup (arr st) a x (ny st ∸ 1)) (λ y′ → lookup (arr st) a x y′) y
eval2 (giny a o) st x y = gated (ny st) (λ y′ → lookup (arr st) a x y′) o y
eval2 (par s)    st x y = lookup (sc st) s
eval2 (con q)    st x y = q
eval2 (p ⊕ q)    st x y = eval2 p st x y +ℚ eval2 q st x y
eval2 (p ⊖ q)    st x y = eval2 p st x y -ℚ eval2 q st x y
eval2 (p ⊗ q)    st x y = eval2 p st x y *ℚ eval2 q st x y
eval2 (p ⊘ q)    st x y = eval2 p st x y /₀ eval2 q st x y
eval2 (neg p)    st x y = - eval2 p st x y
eval2 (max p q)  st x y = eval2 p st x y ⊔ eval2 q st x y
eval2 (min p q)  st x y = eval2 p st x y ⊓ eval2 q st x y

record Kernel2 : Set where
  field
    name    : String
    na ns   : ℕ
    arrays  : Vec String na
    scalars : Vec String ns
    body    : Expr2 na ns
    doc     : String
open Kernel2 public

-- One launch on nb buffers, with np program parameters: which buffers are the kernel's arrays,
-- which parameters are its scalars, and which buffer it writes.
record Launch (nb np : ℕ) : Set where
  constructor launch
  field
    kernel : Kernel2
    ins    : Vec (Fin nb) (na kernel)
    scs    : Vec (Fin np) (ns kernel)
    out    : Fin nb
open Launch public

-- A program: its buffers and parameters by name, and its launches.
record Program : Set where
  field
    name     : String
    nb np    : ℕ
    buffers  : Vec String nb
    params   : Vec String np
    launches : List (Launch nb np)
    result   : Fin nb
    doc      : String
open Program public

module _ {nb np : ℕ} (nx ny : ℕ) (ps : Vec ℚ np) where

  -- The meaning of one launch: the out buffer becomes the kernel's field.
  step : Launch nb np → Vec Field nb → Vec Field nb
  step L bs = bs [ out L ]≔ eval2 (body (kernel L)) (store2 nx ny (map (lookup bs) (ins L)) (map (lookup ps) (scs L)))

  -- The launches in order.
  steps : List (Launch nb np) → Vec Field nb → Vec Field nb
  steps []       bs = bs
  steps (L ∷ Ls) bs = steps Ls (step L bs)

  -- A program run k times.
  repeat : List (Launch nb np) → ℕ → Vec Field nb → Vec Field nb
  repeat Ls zero    bs = bs
  repeat Ls (suc k) bs = steps Ls (repeat Ls k bs)
