{-# OPTIONS --safe --without-K #-}

-- Milestone M4 of ocean-triton/PLAN.md: WAVEWATCH III's discrete interaction approximation of
-- the quadruplet transfer, W3SNL1 (the DIA of Hasselmann et al. 1985), read from
-- model/src/w3snl1md.F90 of metocean/WW3 at tag 7.14.mos-92e2cf6, commit 92e2cf66, and written
-- here statement by statement. The routine, at that commit:
--
--     :335  CONX = TPIINV / SIG(IFR) * CG(IFR)                       IFR = 1 … NFR
--     :338  UE (ISP) = A(ISP) / CONX ;  :339  CON(ISP) = CONX
--     :346  UE(ISP) = UE(ISP-NTH) * FACHFE                         IFR = NFR+1 … NFRHGH
--     :351  UE(ISP) = 0, and SA1 … DA2M too, for ISP = 1-NTH … 0  (:351-359)
--     :368  E00 = UE(ISP)
--     :369  EP1 = AWG1 UE(IP11) + AWG2 UE(IP12) + AWG3 UE(IP13) + AWG4 UE(IP14)   (EM1, EP2, EM2
--           alike with AWG5 … AWG8 and IM11 …, :371-376)
--     :380  FACTOR = CONS * AF11(ISP) * E00
--     :382  SA1A = E00 * ( EP1*DAL1 + EM1*DAL2 ) ;  :383  SA1B = SA1A - EP1*EM1*DAL3 (and SA2A, SA2B)
--     :387  SA1 = FACTOR*SA1B ;  :390  DA1C = CONS*AF11*(SA1A+SA1B) ;  :391  DA1P = FACTOR*(DAL1*E00 - DAL3*EM1)
--     :392  DA1M = FACTOR*(DAL2*E00 - DAL3*EP1)  (and the 2s, :388, :394-396)
--     :404  S(ISP) = CON(ISP) * ( - 2.*(SA1+SA2) + AWG1*(SA1(IC11)+SA2(IC12)) + … + AWG8*(…) )
--     :414  D(ISP) = - 2.*(DA1C+DA2C) + SWG1*(DA1P(IC11)+DA2P(IC12)) + … + SWG4*(…)
--                    + SWG5*(DA1M(IC51)+DA2M(IC52)) + … + SWG8*(…)
--
-- What is taken as data, not computed here: CONS (:324-326, it needs EXP), and the tables that
-- INSNL1 fills once per model (:467-770): the index arrays IP11 … IM24 and IC11 … IC82, the
-- weights AWG1 … AWG8 and SWG1 … SWG8, DAL1 … DAL3, AF11, FACHFE. Every theorem holds for every
-- value of them.
--
-- Positions. Fortran's UE, SA1 … DA2M start at ISP = 1 - NTH; here they start at 0, so position
-- p is ISP + NTH - 1 and the zero rows are p < NTH. The index tables hold such positions. S, D,
-- CON and the IC tables are indexed from 0 by q = ISP - 1. Row r and direction c of a position
-- p ≥ NTH are (p - NTH) / NTH and (p - NTH) mod NTH, and A is read at c + r NTH.
--
-- The kernels: `ue` (one lane per position of UE), the eight `sa1` … `da2m`, then `s` and `d`;
-- eleven launches in the order of the Fortran's loops (`snl1`). `snl1-S` and `snl1-D`: the
-- program's S and D are the routine's S and D at every point, for every input and every table.
module OceanTriton.W3SNL1 where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _⊓_; _<ᵇ_; z≤n; s≤s)
import Data.Nat.Properties as ℕP
open import Data.Nat.DivMod using (_/_; _%_)
open import Data.Product using (_,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_)
open import Data.Rational.Properties using (*-zeroˡ; *-identityˡ)
open import Data.String using (String)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.Vec.Relation.Binary.Pointwise.Inductive using (Pointwise; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; cong₂)
open import Relation.Nullary using (yes; no)
open import Relation.Nullary.Negation using (contradiction)

open import OceanWaves.Order using (_/₀_; 2ℚ)
open import OceanTriton.Gather

-- The inputs of one call: the spectrum A (by q) and the bins' SIG, CG (by row), and the tables.
-- NTH = suc nth′, NFR = suc nfr′; ntail ≥ NFRHGH - NFR bounds the loop of the printed `ue`.
record Snl1 : Set where
  field
    nth′ nfr′ ntail : ℕ
    A sig cg af11   : ℕ → ℚ
    tpiinv fachfe cons dal1 dal2 dal3 : ℚ
    awg swg         : Vec ℚ 8
    ipim ic         : Vec (ℕ → ℕ) 16
open Snl1

module Spec (X : Snl1) where

  nth nfr : ℕ
  nth = suc (nth′ X)
  nfr = suc (nfr′ X)

  row col : ℕ → ℕ
  row p = (p ∸ nth) / nth
  col p = (p ∸ nth) % nth

  awg1 = lookup (awg X) (# 0)
  awg2 = lookup (awg X) (# 1)
  awg3 = lookup (awg X) (# 2)
  awg4 = lookup (awg X) (# 3)
  awg5 = lookup (awg X) (# 4)
  awg6 = lookup (awg X) (# 5)
  awg7 = lookup (awg X) (# 6)
  awg8 = lookup (awg X) (# 7)
  swg1 = lookup (swg X) (# 0)
  swg2 = lookup (swg X) (# 1)
  swg3 = lookup (swg X) (# 2)
  swg4 = lookup (swg X) (# 3)
  swg5 = lookup (swg X) (# 4)
  swg6 = lookup (swg X) (# 5)
  swg7 = lookup (swg X) (# 6)
  swg8 = lookup (swg X) (# 7)
  ip11 = lookup (ipim X) (# 0)
  ip12 = lookup (ipim X) (# 1)
  ip13 = lookup (ipim X) (# 2)
  ip14 = lookup (ipim X) (# 3)
  im11 = lookup (ipim X) (# 4)
  im12 = lookup (ipim X) (# 5)
  im13 = lookup (ipim X) (# 6)
  im14 = lookup (ipim X) (# 7)
  ip21 = lookup (ipim X) (# 8)
  ip22 = lookup (ipim X) (# 9)
  ip23 = lookup (ipim X) (# 10)
  ip24 = lookup (ipim X) (# 11)
  im21 = lookup (ipim X) (# 12)
  im22 = lookup (ipim X) (# 13)
  im23 = lookup (ipim X) (# 14)
  im24 = lookup (ipim X) (# 15)
  ic11 = lookup (ic X) (# 0)
  ic12 = lookup (ic X) (# 1)
  ic21 = lookup (ic X) (# 2)
  ic22 = lookup (ic X) (# 3)
  ic31 = lookup (ic X) (# 4)
  ic32 = lookup (ic X) (# 5)
  ic41 = lookup (ic X) (# 6)
  ic42 = lookup (ic X) (# 7)
  ic51 = lookup (ic X) (# 8)
  ic52 = lookup (ic X) (# 9)
  ic61 = lookup (ic X) (# 10)
  ic62 = lookup (ic X) (# 11)
  ic71 = lookup (ic X) (# 12)
  ic72 = lookup (ic X) (# 13)
  ic81 = lookup (ic X) (# 14)
  ic82 = lookup (ic X) (# 15)

  -- :335
  conx : ℕ → ℚ
  conx r = tpiinv X /₀ sig X r * cg X r

  -- :338 for the rows 0 … NFR - 1, :346 above them.
  ueReal : ℕ → ℕ → ℚ
  ueReal r c = A X (c ℕ.+ r ℕ.* nth) /₀ conx r

  ue : ℕ → ℕ → ℚ
  ueTail : ℕ → ℕ → ℚ
  ue r c = if r <ᵇ nfr then ueReal r c else ueTail r c
  ueTail zero    c = ueReal zero c
  ueTail (suc r) c = ue r c * fachfe X

  -- :351, :338, :346: the array UE by position.
  ueArr : ℕ → ℚ
  ueArr p = if p <ᵇ nth then 0ℚ else ue (row p) (col p)

  -- :364-396 for one position, given the array UE.
  module _ (u : ℕ → ℚ) (p : ℕ) where
    e00 ep1 em1 ep2 em2 fac sa1a sa1b sa2a sa2b : ℚ
    e00  = u p
    ep1  = awg1 * u (ip11 p) + awg2 * u (ip12 p) + awg3 * u (ip13 p) + awg4 * u (ip14 p)
    em1  = awg5 * u (im11 p) + awg6 * u (im12 p) + awg7 * u (im13 p) + awg8 * u (im14 p)
    ep2  = awg1 * u (ip21 p) + awg2 * u (ip22 p) + awg3 * u (ip23 p) + awg4 * u (ip24 p)
    em2  = awg5 * u (im21 p) + awg6 * u (im22 p) + awg7 * u (im23 p) + awg8 * u (im24 p)
    fac  = cons X * af11 X p * e00
    sa1a = e00 * (ep1 * dal1 X + em1 * dal2 X)
    sa1b = sa1a - ep1 * em1 * dal3 X
    sa2a = e00 * (ep2 * dal1 X + em2 * dal2 X)
    sa2b = sa2a - ep2 * em2 * dal3 X

  -- The zero rows (:351-359), then the loop (:364).
  pad : ℚ → ℕ → ℚ
  pad x p = if p <ᵇ nth then 0ℚ else x

  sa1 sa2 da1c da1p da1m da2c da2p da2m : ℕ → ℚ
  sa1  p = pad (fac ueArr p * sa1b ueArr p) p
  sa2  p = pad (fac ueArr p * sa2b ueArr p) p
  da1c p = pad (cons X * af11 X p * (sa1a ueArr p + sa1b ueArr p)) p
  da1p p = pad (fac ueArr p * (dal1 X * e00 ueArr p - dal3 X * em1 ueArr p)) p
  da1m p = pad (fac ueArr p * (dal2 X * e00 ueArr p - dal3 X * ep1 ueArr p)) p
  da2c p = pad (cons X * af11 X p * (sa2a ueArr p + sa2b ueArr p)) p
  da2p p = pad (fac ueArr p * (dal1 X * e00 ueArr p - dal3 X * em2 ueArr p)) p
  da2m p = pad (fac ueArr p * (dal2 X * e00 ueArr p - dal3 X * ep2 ueArr p)) p

  -- :339, :404 and :414, for q = ISP - 1.
  con′ : ℕ → ℚ
  con′ q = conx (q / nth)

  snlS : ℕ → ℚ
  snlS q = con′ q * (- (2ℚ * (sa1 (q ℕ.+ nth) + sa2 (q ℕ.+ nth)))

    + awg1 * (sa1 (ic11 q) + sa2 (ic12 q))
    + awg2 * (sa1 (ic21 q) + sa2 (ic22 q))
    + awg3 * (sa1 (ic31 q) + sa2 (ic32 q))
    + awg4 * (sa1 (ic41 q) + sa2 (ic42 q))
    + awg5 * (sa1 (ic51 q) + sa2 (ic52 q))
    + awg6 * (sa1 (ic61 q) + sa2 (ic62 q))
    + awg7 * (sa1 (ic71 q) + sa2 (ic72 q))
    + awg8 * (sa1 (ic81 q) + sa2 (ic82 q)))

  snlD : ℕ → ℚ
  snlD q = - (2ℚ * (da1c (q ℕ.+ nth) + da2c (q ℕ.+ nth)))
    + swg1 * (da1p (ic11 q) + da2p (ic12 q))
    + swg2 * (da1p (ic21 q) + da2p (ic22 q))
    + swg3 * (da1p (ic31 q) + da2p (ic32 q))
    + swg4 * (da1p (ic41 q) + da2p (ic42 q))
    + swg5 * (da1m (ic51 q) + da2m (ic52 q))
    + swg6 * (da1m (ic61 q) + da2m (ic62 q))
    + swg7 * (da1m (ic71 q) + da2m (ic72 q))
    + swg8 * (da1m (ic81 q) + da2m (ic82 q))

-- ---------------------------------------------------------------------------------------------
-- The kernels

-- Lane p of UE: msk p (0 in the zero rows, else 1) times A(src p) / CONX(kof p) with cnt p
-- factors FACHFE. The host's tables: `tables` below.
ueK : ℕ → KernelG
ueK R = record
  { name = "w3snl1_ue" ; na = 4 ; ni = 3 ; ns = 2 ; nr = 0
  ; arrays = "A" ∷ "sig" ∷ "cg" ∷ "msk" ∷ [] ; idxs = "src" ∷ "kof" ∷ "cnt" ∷ [] ; scalars = "tpiinv" ∷ "fachfe" ∷ []
  ; sums = [] ; reds = []
  ; body = at (# 3) ⊗ rep (gat (# 0) (# 0) ⊘ (par (# 0) ⊘ gat (# 1) (# 1) ⊗ gat (# 2) (# 1))) (# 1) (# 2) R
  ; doc = "UE, the action density over CONX on the extended grid (w3snl1md.F90:335-359)" }

module SA where
  u af m : Fin 3
  u = # 0 ; af = # 1 ; m = # 2
  cons′ dal1′ dal2′ dal3′ : Fin 12
  cons′ = # 0 ; dal1′ = # 1 ; dal2′ = # 2 ; dal3′ = # 3
  ip11′ : ExprG 3 16 12
  ip11′ = gat u (# 0)
  ip12′ : ExprG 3 16 12
  ip12′ = gat u (# 1)
  ip13′ : ExprG 3 16 12
  ip13′ = gat u (# 2)
  ip14′ : ExprG 3 16 12
  ip14′ = gat u (# 3)
  im11′ : ExprG 3 16 12
  im11′ = gat u (# 4)
  im12′ : ExprG 3 16 12
  im12′ = gat u (# 5)
  im13′ : ExprG 3 16 12
  im13′ = gat u (# 6)
  im14′ : ExprG 3 16 12
  im14′ = gat u (# 7)
  ip21′ : ExprG 3 16 12
  ip21′ = gat u (# 8)
  ip22′ : ExprG 3 16 12
  ip22′ = gat u (# 9)
  ip23′ : ExprG 3 16 12
  ip23′ = gat u (# 10)
  ip24′ : ExprG 3 16 12
  ip24′ = gat u (# 11)
  im21′ : ExprG 3 16 12
  im21′ = gat u (# 12)
  im22′ : ExprG 3 16 12
  im22′ = gat u (# 13)
  im23′ : ExprG 3 16 12
  im23′ = gat u (# 14)
  im24′ : ExprG 3 16 12
  im24′ = gat u (# 15)
  wg : ℕ → ExprG 3 16 12
  wg zero = par (# 4) ; wg 1 = par (# 5) ; wg 2 = par (# 6) ; wg 3 = par (# 7)
  wg 4 = par (# 8) ; wg 5 = par (# 9) ; wg 6 = par (# 10) ; wg _ = par (# 11)
  e00 ep1 em1 ep2 em2 fac sa1a sa1b sa2a sa2b : ExprG 3 16 12
  e00  = at u
  ep1  = wg 0 ⊗ ip11′ ⊕ wg 1 ⊗ ip12′ ⊕ wg 2 ⊗ ip13′ ⊕ wg 3 ⊗ ip14′
  em1  = wg 4 ⊗ im11′ ⊕ wg 5 ⊗ im12′ ⊕ wg 6 ⊗ im13′ ⊕ wg 7 ⊗ im14′
  ep2  = wg 0 ⊗ ip21′ ⊕ wg 1 ⊗ ip22′ ⊕ wg 2 ⊗ ip23′ ⊕ wg 3 ⊗ ip24′
  em2  = wg 4 ⊗ im21′ ⊕ wg 5 ⊗ im22′ ⊕ wg 6 ⊗ im23′ ⊕ wg 7 ⊗ im24′
  fac  = par cons′ ⊗ at af ⊗ e00
  sa1a = e00 ⊗ (ep1 ⊗ par dal1′ ⊕ em1 ⊗ par dal2′)
  sa1b = sa1a ⊖ ep1 ⊗ em1 ⊗ par dal3′
  sa2a = e00 ⊗ (ep2 ⊗ par dal1′ ⊕ em2 ⊗ par dal2′)
  sa2b = sa2a ⊖ ep2 ⊗ em2 ⊗ par dal3′

  kern : String → ExprG 3 16 12 → String → KernelG
  kern n e d = record
    { name = n ; na = 3 ; ni = 16 ; ns = 12 ; nr = 0
    ; arrays = "UE" ∷ "af11" ∷ "msk" ∷ []
    ; idxs = "ip11" ∷ "ip12" ∷ "ip13" ∷ "ip14" ∷ "im11" ∷ "im12" ∷ "im13" ∷ "im14" ∷ "ip21" ∷ "ip22" ∷ "ip23" ∷ "ip24" ∷ "im21" ∷ "im22" ∷ "im23" ∷ "im24" ∷ []
    ; scalars = "cons" ∷ "dal1" ∷ "dal2" ∷ "dal3" ∷ "awg1" ∷ "awg2" ∷ "awg3" ∷ "awg4" ∷ "awg5" ∷ "awg6" ∷ "awg7" ∷ "awg8" ∷ []
    ; sums = [] ; reds = [] ; body = at m ⊗ e ; doc = d }

  sa1K : KernelG
  sa1K = kern "w3snl1_sa1" (fac ⊗ sa1b) "SA1 of the DIA (w3snl1md.F90:387)"
  sa2K : KernelG
  sa2K = kern "w3snl1_sa2" (fac ⊗ sa2b) "SA2 of the DIA (w3snl1md.F90:388)"
  da1cK : KernelG
  da1cK = kern "w3snl1_da1c" (par cons′ ⊗ at af ⊗ (sa1a ⊕ sa1b)) "DA1C of the DIA (w3snl1md.F90:390)"
  da1pK : KernelG
  da1pK = kern "w3snl1_da1p" (fac ⊗ (par dal1′ ⊗ e00 ⊖ par dal3′ ⊗ em1)) "DA1P of the DIA (w3snl1md.F90:391)"
  da1mK : KernelG
  da1mK = kern "w3snl1_da1m" (fac ⊗ (par dal2′ ⊗ e00 ⊖ par dal3′ ⊗ ep1)) "DA1M of the DIA (w3snl1md.F90:392)"
  da2cK : KernelG
  da2cK = kern "w3snl1_da2c" (par cons′ ⊗ at af ⊗ (sa2a ⊕ sa2b)) "DA2C of the DIA (w3snl1md.F90:394)"
  da2pK : KernelG
  da2pK = kern "w3snl1_da2p" (fac ⊗ (par dal1′ ⊗ e00 ⊖ par dal3′ ⊗ em2)) "DA2P of the DIA (w3snl1md.F90:395)"
  da2mK : KernelG
  da2mK = kern "w3snl1_da2m" (fac ⊗ (par dal2′ ⊗ e00 ⊖ par dal3′ ⊗ ep2)) "DA2M of the DIA (w3snl1md.F90:396)"
open SA using (sa1K; sa2K; da1cK; da1pK; da1mK; da2cK; da2pK; da2mK)

sK : KernelG
sK = record
  { name = "w3snl1_s" ; na = 4 ; ni = 18 ; ns = 9 ; nr = 0
  ; arrays = "SA1" ∷ "SA2" ∷ "sig" ∷ "cg" ∷ [] ; idxs = "ic11" ∷ "ic12" ∷ "ic21" ∷ "ic22" ∷ "ic31" ∷ "ic32" ∷ "ic41" ∷ "ic42" ∷ "ic51" ∷ "ic52" ∷ "ic61" ∷ "ic62" ∷ "ic71" ∷ "ic72" ∷ "ic81" ∷ "ic82" ∷ "kofS" ∷ "self" ∷ []
  ; scalars = "tpiinv" ∷ "awg1" ∷ "awg2" ∷ "awg3" ∷ "awg4" ∷ "awg5" ∷ "awg6" ∷ "awg7" ∷ "awg8" ∷ [] ; sums = [] ; reds = []
  ; body = (par (# 0) ⊘ gat (# 2) (# 16) ⊗ gat (# 3) (# 16))
           ⊗ (neg (con 2ℚ ⊗ (gat (# 0) (# 17) ⊕ gat (# 1) (# 17))) ⊕ par (# 1) ⊗ (gat (# 0) (# 0) ⊕ gat (# 1) (# 1)) ⊕ par (# 2) ⊗ (gat (# 0) (# 2) ⊕ gat (# 1) (# 3)) ⊕ par (# 3) ⊗ (gat (# 0) (# 4) ⊕ gat (# 1) (# 5)) ⊕ par (# 4) ⊗ (gat (# 0) (# 6) ⊕ gat (# 1) (# 7)) ⊕ par (# 5) ⊗ (gat (# 0) (# 8) ⊕ gat (# 1) (# 9)) ⊕ par (# 6) ⊗ (gat (# 0) (# 10) ⊕ gat (# 1) (# 11)) ⊕ par (# 7) ⊗ (gat (# 0) (# 12) ⊕ gat (# 1) (# 13)) ⊕ par (# 8) ⊗ (gat (# 0) (# 14) ⊕ gat (# 1) (# 15)))
  ; doc = "S of the DIA (w3snl1md.F90:404)" }

dK : KernelG
dK = record
  { name = "w3snl1_d" ; na = 6 ; ni = 17 ; ns = 8 ; nr = 0
  ; arrays = "DA1C" ∷ "DA2C" ∷ "DA1P" ∷ "DA2P" ∷ "DA1M" ∷ "DA2M" ∷ [] ; idxs = "ic11" ∷ "ic12" ∷ "ic21" ∷ "ic22" ∷ "ic31" ∷ "ic32" ∷ "ic41" ∷ "ic42" ∷ "ic51" ∷ "ic52" ∷ "ic61" ∷ "ic62" ∷ "ic71" ∷ "ic72" ∷ "ic81" ∷ "ic82" ∷ "self" ∷ []
  ; scalars = "swg1" ∷ "swg2" ∷ "swg3" ∷ "swg4" ∷ "swg5" ∷ "swg6" ∷ "swg7" ∷ "swg8" ∷ [] ; sums = [] ; reds = []
  ; body = neg (con 2ℚ ⊗ (gat (# 0) (# 16) ⊕ gat (# 1) (# 16))) ⊕ par (# 0) ⊗ (gat (# 2) (# 0) ⊕ gat (# 3) (# 1)) ⊕ par (# 1) ⊗ (gat (# 2) (# 2) ⊕ gat (# 3) (# 3)) ⊕ par (# 2) ⊗ (gat (# 2) (# 4) ⊕ gat (# 3) (# 5)) ⊕ par (# 3) ⊗ (gat (# 2) (# 6) ⊕ gat (# 3) (# 7)) ⊕ par (# 4) ⊗ (gat (# 4) (# 8) ⊕ gat (# 5) (# 9)) ⊕ par (# 5) ⊗ (gat (# 4) (# 10) ⊕ gat (# 5) (# 11)) ⊕ par (# 6) ⊗ (gat (# 4) (# 12) ⊕ gat (# 5) (# 13)) ⊕ par (# 7) ⊗ (gat (# 4) (# 14) ⊕ gat (# 5) (# 15))
  ; doc = "D, the diagonal of the DIA (w3snl1md.F90:414)" }

-- The eleven launches, in the order of the Fortran's loops.
snl1Launches : ℕ → List (LaunchG 16 37 22 3)
snl1Launches R =
  launchG (ueK R) (# 0 ∷ # 1 ∷ # 2 ∷ # 3 ∷ []) (# 0 ∷ # 1 ∷ # 2 ∷ []) (# 0 ∷ # 1 ∷ []) (# 0) (# 5) ∷
  launchG sa1K (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 6) ∷
  launchG sa2K (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 7) ∷
  launchG da1cK (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 8) ∷
  launchG da1pK (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 9) ∷
  launchG da1mK (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 10) ∷
  launchG da2cK (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 11) ∷
  launchG da2pK (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 12) ∷
  launchG da2mK (# 5 ∷ # 4 ∷ # 3 ∷ []) (# 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ # 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ []) (# 2 ∷ # 3 ∷ # 4 ∷ # 5 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 1) (# 13) ∷
  launchG sK (# 6 ∷ # 7 ∷ # 1 ∷ # 2 ∷ []) (# 19 ∷ # 20 ∷ # 21 ∷ # 22 ∷ # 23 ∷ # 24 ∷ # 25 ∷ # 26 ∷ # 27 ∷ # 28 ∷ # 29 ∷ # 30 ∷ # 31 ∷ # 32 ∷ # 33 ∷ # 34 ∷ # 35 ∷ # 36 ∷ []) (# 0 ∷ # 6 ∷ # 7 ∷ # 8 ∷ # 9 ∷ # 10 ∷ # 11 ∷ # 12 ∷ # 13 ∷ []) (# 2) (# 14) ∷
  launchG dK (# 8 ∷ # 11 ∷ # 9 ∷ # 12 ∷ # 10 ∷ # 13 ∷ []) (# 19 ∷ # 20 ∷ # 21 ∷ # 22 ∷ # 23 ∷ # 24 ∷ # 25 ∷ # 26 ∷ # 27 ∷ # 28 ∷ # 29 ∷ # 30 ∷ # 31 ∷ # 32 ∷ # 33 ∷ # 34 ∷ # 36 ∷ []) (# 14 ∷ # 15 ∷ # 16 ∷ # 17 ∷ # 18 ∷ # 19 ∷ # 20 ∷ # 21 ∷ []) (# 2) (# 15) ∷ []

snl1 : ℕ → ProgramG
snl1 R = record
  { name = "w3snl1" ; nb = 16 ; nx = 37 ; np = 22 ; nl = 3
  ; buffers = "A" ∷ "sig" ∷ "cg" ∷ "msk" ∷ "af11" ∷ "UE" ∷ "SA1" ∷ "SA2" ∷ "DA1C" ∷ "DA1P" ∷ "DA1M" ∷ "DA2C" ∷ "DA2P" ∷ "DA2M" ∷ "S" ∷ "D" ∷ []
  ; indices = "src" ∷ "kof" ∷ "cnt" ∷ "ip11" ∷ "ip12" ∷ "ip13" ∷ "ip14" ∷ "im11" ∷ "im12" ∷ "im13" ∷ "im14" ∷ "ip21" ∷ "ip22" ∷ "ip23" ∷ "ip24" ∷ "im21" ∷ "im22" ∷ "im23" ∷ "im24" ∷ "ic11" ∷ "ic12" ∷ "ic21" ∷ "ic22" ∷ "ic31" ∷ "ic32" ∷ "ic41" ∷ "ic42" ∷ "ic51" ∷ "ic52" ∷ "ic61" ∷ "ic62" ∷ "ic71" ∷ "ic72" ∷ "ic81" ∷ "ic82" ∷ "kofS" ∷ "self" ∷ []
  ; params = "tpiinv" ∷ "fachfe" ∷ "cons" ∷ "dal1" ∷ "dal2" ∷ "dal3" ∷ "awg1" ∷ "awg2" ∷ "awg3" ∷ "awg4" ∷ "awg5" ∷ "awg6" ∷ "awg7" ∷ "awg8" ∷ "swg1" ∷ "swg2" ∷ "swg3" ∷ "swg4" ∷ "swg5" ∷ "swg6" ∷ "swg7" ∷ "swg8" ∷ []
  ; sizes = "nue" ∷ "nsa" ∷ "nspec" ∷ []
  ; launches = snl1Launches R ; results = (# 14 , # 2) ∷ (# 15 , # 2) ∷ []
  ; doc = "WAVEWATCH III's DIA, W3SNL1 (w3snl1md.F90:335-414)" }

-- ---------------------------------------------------------------------------------------------
-- The host's tables and buffers

module _ (X : Snl1) where
  open Spec X using (nth; row; col)

  msk : ℕ → ℚ
  msk p = if p <ᵇ nth then 0ℚ else 1ℚ

  -- UE above the last real row is the last real row times FACHFE, once per row (:346).
  srcT kofT cntT kofST selfT : ℕ → ℕ
  srcT p  = col p ℕ.+ (row p ⊓ nfr′ X) ℕ.* nth
  kofT p  = row p ⊓ nfr′ X
  cntT p  = row p ∸ nfr′ X
  kofST q = q / nth
  selfT q = q ℕ.+ nth

  tables : Vec (ℕ → ℕ) 37
  tables = srcT ∷ kofT ∷ cntT ∷ lookup (ipim X) (# 0) ∷ lookup (ipim X) (# 1) ∷ lookup (ipim X) (# 2) ∷ lookup (ipim X) (# 3) ∷ lookup (ipim X) (# 4) ∷ lookup (ipim X) (# 5) ∷ lookup (ipim X) (# 6) ∷ lookup (ipim X) (# 7) ∷ lookup (ipim X) (# 8) ∷ lookup (ipim X) (# 9) ∷ lookup (ipim X) (# 10) ∷ lookup (ipim X) (# 11) ∷ lookup (ipim X) (# 12) ∷ lookup (ipim X) (# 13) ∷ lookup (ipim X) (# 14) ∷ lookup (ipim X) (# 15)
    ∷ lookup (ic X) (# 0) ∷ lookup (ic X) (# 1) ∷ lookup (ic X) (# 2) ∷ lookup (ic X) (# 3) ∷ lookup (ic X) (# 4) ∷ lookup (ic X) (# 5) ∷ lookup (ic X) (# 6) ∷ lookup (ic X) (# 7) ∷ lookup (ic X) (# 8) ∷ lookup (ic X) (# 9) ∷ lookup (ic X) (# 10) ∷ lookup (ic X) (# 11) ∷ lookup (ic X) (# 12) ∷ lookup (ic X) (# 13) ∷ lookup (ic X) (# 14) ∷ lookup (ic X) (# 15) ∷ kofST ∷ selfT ∷ []

  params0 : Vec ℚ 22
  params0 = tpiinv X ∷ fachfe X ∷ cons X ∷ dal1 X ∷ dal2 X ∷ dal3 X
    ∷ lookup (awg X) (# 0) ∷ lookup (awg X) (# 1) ∷ lookup (awg X) (# 2) ∷ lookup (awg X) (# 3) ∷ lookup (awg X) (# 4) ∷ lookup (awg X) (# 5) ∷ lookup (awg X) (# 6) ∷ lookup (awg X) (# 7)
    ∷ lookup (swg X) (# 0) ∷ lookup (swg X) (# 1) ∷ lookup (swg X) (# 2) ∷ lookup (swg X) (# 3) ∷ lookup (swg X) (# 4) ∷ lookup (swg X) (# 5) ∷ lookup (swg X) (# 6) ∷ lookup (swg X) (# 7) ∷ []

  -- The lane counts: UE's positions, SA's positions, and NSPEC.
  module _ (ls : Vec ℕ 3) where

    buffers0 : Vec (ℕ → ℚ) 16
    buffers0 = A X ∷ sig X ∷ cg X ∷ msk ∷ af11 X ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ []
      where z = λ _ → 0ℚ

    result : Vec (ℕ → ℚ) 16
    result = stepsG tables params0 ls (snl1Launches (ntail X)) buffers0

-- ---------------------------------------------------------------------------------------------
-- The proof: the program is the routine

private
  ltb-true : ∀ m n → m ℕ.< n → (m <ᵇ n) ≡ true
  ltb-true zero    (suc n) _       = refl
  ltb-true (suc m) (suc n) (s≤s h) = ltb-true m n h

  ltb-false : ∀ m n → n ℕ.≤ m → (m <ᵇ n) ≡ false
  ltb-false m       zero    _       = refl
  ltb-false (suc m) (suc n) (s≤s h) = ltb-false m n h

  -- msk times a value is the zero rows' 0, or the value.
  pad1 : ∀ (b : Bool) (x y : ℚ) → x ≡ y → (if b then 0ℚ else 1ℚ) * x ≡ (if b then 0ℚ else y)
  pad1 true  x y _ = *-zeroˡ x
  pad1 false x y e = trans (*-identityˡ x) e

module Proof (X : Snl1) (ls : Vec ℕ 3) where
  open Spec X

  -- UE above the real rows, in closed form: the last real row and r - (NFR - 1) factors.
  ue-closed : ∀ r c → ue r c ≡ repN (r ∸ nfr′ X) (fachfe X) (ueReal (r ⊓ nfr′ X) c)
  ue-closed r c with r ℕP.≤? nfr′ X
  ... | yes h rewrite ltb-true r nfr (s≤s h) | ℕP.m≤n⇒m∸n≡0 h | ℕP.m≤n⇒m⊓n≡m h = refl
  ue-closed zero    c | no ¬h = contradiction z≤n ¬h
  ue-closed (suc r) c | no ¬h =
    trans (cong (λ b → if b then ueReal (suc r) c else ueTail (suc r) c) (ltb-false (suc r) nfr (ℕP.≰⇒> ¬h)))
    (trans (cong (_* fachfe X) (ue-closed r c))
           (cong₂ (λ m k → repN m (fachfe X) (ueReal k c)) (sym (ℕP.+-∸-assoc 1 h′))
                  (trans (ℕP.m≥n⇒m⊓n≡n h′) (sym (ℕP.m≥n⇒m⊓n≡n (ℕP.m≤n⇒m≤1+n h′))))))
    where h′ = ℕ.s≤s⁻¹ (ℕP.≰⇒> ¬h)

  UEk : ℕ → ℚ
  UEk = runG (ueK (ntail X)) (lookup ls (# 0)) (sg (A X ∷ sig X ∷ cg X ∷ msk X ∷ []) (srcT X ∷ kofT X ∷ cntT X ∷ []) (tpiinv X ∷ fachfe X ∷ []))

  ue-sound : ∀ p → UEk p ≡ ueArr p
  ue-sound p = pad1 (p <ᵇ nth) _ _ (sym (ue-closed (row p) (col p)))

  ipT : Vec (ℕ → ℕ) 16
  ipT = lookup (ipim X) (# 0) ∷ lookup (ipim X) (# 1) ∷ lookup (ipim X) (# 2) ∷ lookup (ipim X) (# 3) ∷ lookup (ipim X) (# 4) ∷ lookup (ipim X) (# 5) ∷ lookup (ipim X) (# 6) ∷ lookup (ipim X) (# 7) ∷ lookup (ipim X) (# 8) ∷ lookup (ipim X) (# 9) ∷ lookup (ipim X) (# 10) ∷ lookup (ipim X) (# 11) ∷ lookup (ipim X) (# 12) ∷ lookup (ipim X) (# 13) ∷ lookup (ipim X) (# 14) ∷ lookup (ipim X) (# 15) ∷ []

  saSc : Vec ℚ 12
  saSc = cons X ∷ dal1 X ∷ dal2 X ∷ dal3 X ∷ lookup (awg X) (# 0) ∷ lookup (awg X) (# 1) ∷ lookup (awg X) (# 2) ∷ lookup (awg X) (# 3) ∷ lookup (awg X) (# 4) ∷ lookup (awg X) (# 5) ∷ lookup (awg X) (# 6) ∷ lookup (awg X) (# 7) ∷ []

  saStore : StoreG 3 16 12
  saStore = sg (UEk ∷ af11 X ∷ msk X ∷ []) ipT saSc

  private
    pad2 : ∀ (b : Bool) (x : ℚ) → (if b then 0ℚ else 1ℚ) * x ≡ (if b then 0ℚ else x)
    pad2 b x = pad1 b x x refl

  sa1-sound : ∀ p → runG SA.sa1K (lookup ls (# 1)) saStore p ≡ sa1 p
  sa1-sound p = trans (runG-cong SA.sa1K (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  sa2-sound : ∀ p → runG SA.sa2K (lookup ls (# 1)) saStore p ≡ sa2 p
  sa2-sound p = trans (runG-cong SA.sa2K (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  da1c-sound : ∀ p → runG SA.da1cK (lookup ls (# 1)) saStore p ≡ da1c p
  da1c-sound p = trans (runG-cong SA.da1cK (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  da1p-sound : ∀ p → runG SA.da1pK (lookup ls (# 1)) saStore p ≡ da1p p
  da1p-sound p = trans (runG-cong SA.da1pK (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  da1m-sound : ∀ p → runG SA.da1mK (lookup ls (# 1)) saStore p ≡ da1m p
  da1m-sound p = trans (runG-cong SA.da1mK (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  da2c-sound : ∀ p → runG SA.da2cK (lookup ls (# 1)) saStore p ≡ da2c p
  da2c-sound p = trans (runG-cong SA.da2cK (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  da2p-sound : ∀ p → runG SA.da2pK (lookup ls (# 1)) saStore p ≡ da2p p
  da2p-sound p = trans (runG-cong SA.da2pK (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  da2m-sound : ∀ p → runG SA.da2mK (lookup ls (# 1)) saStore p ≡ da2m p
  da2m-sound p = trans (runG-cong SA.da2mK (lookup ls (# 1)) {UEk ∷ af11 X ∷ msk X ∷ []} {ueArr ∷ af11 X ∷ msk X ∷ []} ipT saSc
                         (ue-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) p)
                      (pad2 (p <ᵇ nth) _)

  -- The program's S and D are the routine's.
  snl1-S : ∀ q → lookup (result X ls) (# 14) q ≡ snlS q
  snl1-S q = runG-cong sK (lookup ls (# 2)) {runG SA.sa1K (lookup ls (# 1)) saStore ∷ runG SA.sa2K (lookup ls (# 1)) saStore ∷ sig X ∷ cg X ∷ []} {sa1 ∷ sa2 ∷ sig X ∷ cg X ∷ []}
               (lookup (ic X) (# 0) ∷ lookup (ic X) (# 1) ∷ lookup (ic X) (# 2) ∷ lookup (ic X) (# 3) ∷ lookup (ic X) (# 4) ∷ lookup (ic X) (# 5) ∷ lookup (ic X) (# 6) ∷ lookup (ic X) (# 7) ∷ lookup (ic X) (# 8) ∷ lookup (ic X) (# 9) ∷ lookup (ic X) (# 10) ∷ lookup (ic X) (# 11) ∷ lookup (ic X) (# 12) ∷ lookup (ic X) (# 13) ∷ lookup (ic X) (# 14) ∷ lookup (ic X) (# 15) ∷ kofST X ∷ selfT X ∷ []) (tpiinv X ∷ lookup (awg X) (# 0) ∷ lookup (awg X) (# 1) ∷ lookup (awg X) (# 2) ∷ lookup (awg X) (# 3) ∷ lookup (awg X) (# 4) ∷ lookup (awg X) (# 5) ∷ lookup (awg X) (# 6) ∷ lookup (awg X) (# 7) ∷ [])
               (sa1-sound ∷ sa2-sound ∷ (λ _ → refl) ∷ (λ _ → refl) ∷ []) q

  snl1-D : ∀ q → lookup (result X ls) (# 15) q ≡ snlD q
  snl1-D q = runG-cong dK (lookup ls (# 2))
               {runG SA.da1cK (lookup ls (# 1)) saStore ∷ runG SA.da2cK (lookup ls (# 1)) saStore ∷ runG SA.da1pK (lookup ls (# 1)) saStore ∷ runG SA.da2pK (lookup ls (# 1)) saStore ∷ runG SA.da1mK (lookup ls (# 1)) saStore ∷ runG SA.da2mK (lookup ls (# 1)) saStore ∷ []}
               {da1c ∷ da2c ∷ da1p ∷ da2p ∷ da1m ∷ da2m ∷ []}
               (lookup (ic X) (# 0) ∷ lookup (ic X) (# 1) ∷ lookup (ic X) (# 2) ∷ lookup (ic X) (# 3) ∷ lookup (ic X) (# 4) ∷ lookup (ic X) (# 5) ∷ lookup (ic X) (# 6) ∷ lookup (ic X) (# 7) ∷ lookup (ic X) (# 8) ∷ lookup (ic X) (# 9) ∷ lookup (ic X) (# 10) ∷ lookup (ic X) (# 11) ∷ lookup (ic X) (# 12) ∷ lookup (ic X) (# 13) ∷ lookup (ic X) (# 14) ∷ lookup (ic X) (# 15) ∷ selfT X ∷ []) (lookup (swg X) (# 0) ∷ lookup (swg X) (# 1) ∷ lookup (swg X) (# 2) ∷ lookup (swg X) (# 3) ∷ lookup (swg X) (# 4) ∷ lookup (swg X) (# 5) ∷ lookup (swg X) (# 6) ∷ lookup (swg X) (# 7) ∷ [])
               (da1c-sound ∷ da2c-sound ∷ da1p-sound ∷ da2p-sound ∷ da1m-sound ∷ da2m-sound ∷ []) q

