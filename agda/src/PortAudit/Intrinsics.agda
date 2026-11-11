{-# OPTIONS --safe --without-K #-}

-- Group U of the port audit of chaceon (`tools/port-audit/Chaceon.hs`, `port-audit/README.md`):
-- Fortran's intrinsics in rust/crates/ww3-kernels/src/util.rs at the commit that `Chaceon.hs`
-- pins, over IEEE f32 (`PortAudit.Float32`). The names follow Z3, with `-` for `_`.
--
-- * nint = round half away (util.rs:21-31): `t = x as i32; frac = x - t as f32`, then t + 1
--   when frac ≥ 0.5 and t - 1 when frac ≤ -0.5. It is gfortran's NINT, ties away from zero, for
--   every f32 x in (-2^31, 2^31).
-- * nint_frac_exact (util.rs:24): `t as f32 + frac` gives x back, so `x - t` is exact.
-- * floor = round down (util.rs:34-37): `t = x as i32`, then t - 1 when t > x.
-- * sign = SIGN(A, B) and sign_negative_zero (util.rs:41-43): the magnitude bits of a with the
--   sign bit of b is Fortran's SIGN, and SIGN(a, -0.) is -|a|, as gfortran gives.
--
-- Z3 proves each one for every f32 in its floating-point theory; Agda proves it for every bit
-- pattern of the model. The proof of nint and floor goes through the exact parts of x: its
-- integer part q and its fraction r, in units of 2^-149 (`Parts`). `t as f32` and `x - t` are
-- exact (`PortAudit.Float32Exact.round-exact`), so the rounded operations give q and r.
module PortAudit.Intrinsics where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
open import Data.Integer as ℤ using (ℤ; +_; -[1+_])
import Data.Integer.Properties as ℤₚ
open import Data.Nat as ℕ using (ℕ; zero; suc; _+_; _*_; _∸_; _^_; _<ᵇ_; _≤ᵇ_; _≤_; _<_; z≤n; s≤s)
import Data.Nat.Properties as ℕₚ
open import Data.Nat.DivMod using (m*n/n≡m)
open import Data.Product using (Σ; _×_; _,_; proj₁; proj₂)
open import Data.Vec using (Vec; []; _∷_; _++_; replicate; zipWith)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import PortAudit.Float32
open import PortAudit.Float32Exact

-- ---------------------------------------------------------------------------------------------
-- The code (util.rs), as Chaceon.hs states it

-- 2^31 and 0.5.
big half : Float32
big  = ofWord 0x4F000000
half = ofWord 0x3F000000

-- x in (-2^31, 2^31) and not NaN.
inI32 : Float32 → Bool
inI32 x = lt x big ∧ gt x (neg big) ∧ not (isNaN x)

frac-of : Float32 → Float32
frac-of x = sub x (fromI32 (toI32 x))

nintB : ℤ → Bool → Bool → ℤ
nintB t true  _     = t ℤ.+ + 1
nintB t false true  = t ℤ.- + 1
nintB t false false = t

-- util.rs:21-31
nint : Float32 → ℤ
nint x = nintB (toI32 x) (ge (frac-of x) half) (le (frac-of x) (neg half))

floorB : ℤ → Bool → ℤ
floorB t true  = t ℤ.- + 1
floorB t false = t

-- util.rs:34-37
floor′ : Float32 → ℤ
floor′ x = floorB (toI32 x) (gt (fromI32 (toI32 x)) x)

-- util.rs:41-43: (a.to_bits() & 0x7fffffff) | (b.to_bits() & 0x80000000).
_&_ _∣_ : Word32 → Word32 → Word32
_&_ = zipWith _∧_
_∣_ = zipWith _∨_

signBits : Float32 → Float32 → Word32
signBits a b = (bits a & fromℕ 32 0x7fffffff) ∣ (bits b & fromℕ 32 0x80000000)

-- Chaceon.hs's fsign, Fortran's SIGN(mag, s): -|mag| when s is negative (-0 included), else |mag|.
fsignB : Float32 → Bool → Float32
fsignB mag true  = neg (abs mag)
fsignB mag false = abs mag

fsign : Float32 → Float32 → Float32
fsign mag s = fsignB mag (isNegative s)

-- ---------------------------------------------------------------------------------------------
-- A float in range is finite

private
  H : ℕ
  H = 2 ^ 148          -- 0.5 in units of 2^-149

  fin-of : ∀ k → (ltK k (classify big) ∧ ltK (classify (neg big)) k ∧ not (isNaNK k)) ≡ true →
           Σ Bool λ s → Σ ℕ λ V → k ≡ fin s V
  fin-of nan         ()
  fin-of (inf true)  ()
  fin-of (inf false) ()
  fin-of (fin s V)   _ = s , V , refl

-- ---------------------------------------------------------------------------------------------
-- The parts of a finite float

-- How the signs of x, of `t as f32` and of the fraction go together, by the integer part q and
-- the fraction r: x ≥ 0; x < 0 an integer; x < 0 with a fraction; x in (-1, 0].
data Shape : Bool → Bool → Bool → ℕ → ℕ → Set where
  pos       : ∀ {q r} → Shape false false false q r
  neg-int   : ∀ {q}   → 0 < q → Shape true true false q 0
  neg-frac  : ∀ {q r} → 0 < q → Shape true true true q (suc r)
  neg-small : ∀ {r}   → Shape true false true 0 r

record Parts (x : Float32) : Set where
  constructor parts-of
  field
    s s′ s₁ : Bool
    V q r   : ℕ
    kx      : classify x ≡ fin s V
    repV    : Repr V
    q≡      : q ≡ V /2^ 149
    r≡      : r ≡ V %2^ 149
    V≡      : V ≡ r + q * U
    t0≡     : toI32 x ≡ applySign s (+ q)
    ky      : classify (fromI32 (toI32 x)) ≡ fin s′ (q * U)
    kf      : classify (frac-of x) ≡ fin s₁ r
    shape   : Shape s s′ s₁ q r

private
  -- The fraction: x + (- t as f32), with the signs that x and t have.
  frac-sum : ∀ x {s V s′ m} → classify x ≡ fin s V → classify (fromI32 (toI32 x)) ≡ fin s′ m →
             classify (frac-of x) ≡ classify (addFin s V (not s′) m)
  frac-sum x {s} {V} {s′} {m} kx ky =
    cong₂ (λ a b → classify (addK x (neg y) a b)) kx (trans (classify-neg y) (cong negK ky))
    where y = fromI32 (toI32 x)

  V≡of : ∀ V q r → q ≡ V /2^ 149 → r ≡ V %2^ 149 → V ≡ r + q * U
  V≡of V q r q≡ r≡ = trans (V≡r+qU V) (cong₂ (λ a b → a + b * U) (sym r≡) (sym q≡))

  t0≡of : ∀ x {s V} q → classify x ≡ fin s V → q ≡ V /2^ 149 → toI32 x ≡ applySign s (+ q)
  t0≡of x {s} q kx q≡ = trans (cong toI32K kx) (cong (λ n → applySign s (+ n)) (sym q≡))

  qU-repr : ∀ {V} q → Repr V → q ≡ V /2^ 149 → Repr (q * U)
  qU-repr q rp q≡ = subst (λ n → Repr (n * U)) (sym q≡) (int-repr rp)

  r-repr : ∀ {V} r → Repr V → r ≡ V %2^ 149 → Repr r
  r-repr r rp r≡ = subst Repr (sym r≡) (frac-repr rp)

  V∸qU : ∀ V q r → V ≡ r + q * U → V ∸ q * U ≡ r
  V∸qU V q r V≡ = trans (cong (_∸ q * U) V≡) (ℕₚ.m+n∸n≡m r (q * U))

  qU<V : ∀ V q r → V ≡ suc r + q * U → q * U < V
  qU<V V q r V≡ = subst (q * U <_) (sym V≡) (ℕₚ.m<n+m (q * U) (s≤s z≤n))

  -- The fraction when it is not zero: x - t is |r| with the sign of x.
  frac-gt : ∀ s V q r → V ≡ suc r + q * U → Repr (suc r) →
            classify (cancelB s V (not s) (q * U) (q * U <ᵇ V) (V <ᵇ q * U)) ≡ fin s (suc r)
  frac-gt s V q r V≡ rp =
    trans (cancel-gt s V (not s) (q * U) (qU<V V q r V≡) (subst Repr (sym (V∸qU V q (suc r) V≡)) rp))
          (cong (fin s) (V∸qU V q (suc r) V≡))

parts′ : ∀ x s V q r → classify x ≡ fin s V → Repr V → q ≡ V /2^ 149 → r ≡ V %2^ 149 → Parts x
parts′ x false V q zero kx rp q≡ r≡ = record
  { s = false ; s′ = false ; s₁ = false ; V = V ; q = q ; r = 0 ; kx = kx ; repV = rp ; q≡ = q≡ ; r≡ = r≡
  ; V≡ = V≡ ; t0≡ = t0≡ ; ky = ky
  ; kf = trans (frac-sum x kx ky) (cancel-eq false V true (q * U) (trans V≡ (ℕₚ.+-identityˡ (q * U))))
  ; shape = pos }
  where
    V≡ = V≡of V q 0 q≡ r≡
    t0≡ = t0≡of x q kx q≡
    ky : classify (fromI32 (toI32 x)) ≡ fin false (q * U)
    ky = trans (cong (λ t → classify (fromI32 t)) t0≡) (round-exact false (q * U) (qU-repr q rp q≡))
parts′ x false V q (suc r) kx rp q≡ r≡ = record
  { s = false ; s′ = false ; s₁ = false ; V = V ; q = q ; r = suc r ; kx = kx ; repV = rp ; q≡ = q≡ ; r≡ = r≡
  ; V≡ = V≡ ; t0≡ = t0≡ ; ky = ky
  ; kf = trans (frac-sum x kx ky) (frac-gt false V q r V≡ (r-repr (suc r) rp r≡))
  ; shape = pos }
  where
    V≡ = V≡of V q (suc r) q≡ r≡
    t0≡ = t0≡of x q kx q≡
    ky : classify (fromI32 (toI32 x)) ≡ fin false (q * U)
    ky = trans (cong (λ t → classify (fromI32 t)) t0≡) (round-exact false (q * U) (qU-repr q rp q≡))
parts′ x true V zero r kx rp q≡ r≡ = record
  { s = true ; s′ = false ; s₁ = true ; V = V ; q = 0 ; r = r ; kx = kx ; repV = rp ; q≡ = q≡ ; r≡ = r≡
  ; V≡ = V≡ ; t0≡ = t0≡ ; ky = ky
  ; kf = trans (frac-sum x kx ky)
               (trans (round-exact true (V + 0) (subst Repr (sym (ℕₚ.+-identityʳ V)) rp))
                      (cong (fin true) (trans (ℕₚ.+-identityʳ V) (trans V≡ (ℕₚ.+-identityʳ r)))))
  ; shape = neg-small }
  where
    V≡ = V≡of V 0 r q≡ r≡
    t0≡ = t0≡of x 0 kx q≡
    ky : classify (fromI32 (toI32 x)) ≡ fin false 0
    ky = trans (cong (λ t → classify (fromI32 t)) t0≡) (round-exact false 0 (repr 0 0 (2^>0 24) z≤n refl))
parts′ x true V (suc q) zero kx rp q≡ r≡ = record
  { s = true ; s′ = true ; s₁ = false ; V = V ; q = suc q ; r = 0 ; kx = kx ; repV = rp ; q≡ = q≡ ; r≡ = r≡
  ; V≡ = V≡ ; t0≡ = t0≡ ; ky = ky
  ; kf = trans (frac-sum x kx ky) (cancel-eq true V false (suc q * U) (trans V≡ (ℕₚ.+-identityˡ (suc q * U))))
  ; shape = neg-int (s≤s z≤n) }
  where
    V≡ = V≡of V (suc q) 0 q≡ r≡
    t0≡ = t0≡of x (suc q) kx q≡
    ky : classify (fromI32 (toI32 x)) ≡ fin true (suc q * U)
    ky = trans (cong (λ t → classify (fromI32 t)) t0≡) (round-exact true (suc q * U) (qU-repr (suc q) rp q≡))
parts′ x true V (suc q) (suc r) kx rp q≡ r≡ = record
  { s = true ; s′ = true ; s₁ = true ; V = V ; q = suc q ; r = suc r ; kx = kx ; repV = rp ; q≡ = q≡ ; r≡ = r≡
  ; V≡ = V≡ ; t0≡ = t0≡ ; ky = ky
  ; kf = trans (frac-sum x kx ky) (frac-gt true V (suc q) r V≡ (r-repr (suc r) rp r≡))
  ; shape = neg-frac (s≤s z≤n) }
  where
    V≡ = V≡of V (suc q) (suc r) q≡ r≡
    t0≡ = t0≡of x (suc q) kx q≡
    ky : classify (fromI32 (toI32 x)) ≡ fin true (suc q * U)
    ky = trans (cong (λ t → classify (fromI32 t)) t0≡) (round-exact true (suc q * U) (qU-repr (suc q) rp q≡))

parts : ∀ x → inI32 x ≡ true → Parts x
parts x p with fin-of (classify x) p
... | s , V , kx = parts′ x s V _ _ kx (proj₂ (classify-fin x kx)) refl refl

-- ---------------------------------------------------------------------------------------------
-- Small facts

private
  U≤ᵇ0 : (U ≤ᵇ 0) ≡ false
  U≤ᵇ0 = cong (_≤ᵇ 0) U≡

  -- 2r ≥ 2^149 exactly when r ≥ 2^148: the tie of RNA is the half of `nint`.
  half-bit : ∀ r → (U ≤ᵇ 2 * r) ≡ not (r <ᵇ H)
  half-bit r with r <ᵇ H in eq
  ... | true  = trans (cong (_≤ᵇ 2 * r) U≡)
                      (≤ᵇ-false {2 ^ 149} {2 * r} (ℕₚ.*-monoʳ-< 2 {r} {H} (<ᵇ⇒< {r} {H} eq)))
  ... | false = trans (cong (_≤ᵇ 2 * r) U≡)
                      (≤ᵇ-true {2 ^ 149} {2 * r} (ℕₚ.*-monoʳ-≤ 2 {H} {r} (<ᵇ⇒≥ {r} {H} eq)))

  bit≤1 : ∀ b → bitN b ≤ 1
  bit≤1 true  = s≤s z≤n
  bit≤1 false = z≤n

  snz-H : ∀ r → someNonZero r H ≡ true
  snz-H zero    = refl
  snz-H (suc r) = refl

  snz-0 : ∀ V → someNonZero V 0 ≡ (0 <ᵇ V)
  snz-0 zero    = refl
  snz-0 (suc V) = refl

  U>0 : 0 < U
  U>0 = subst (0 <_) (sym U≡) (2^>0 149)

  qU>0 : ∀ q → 0 < q → 0 < q * U
  qU>0 (suc q) _ = ℕₚ.<-≤-trans U>0 (ℕₚ.m≤m+n U (q * U))

  neg-minus-one : ∀ q → applySign true (+ q) ℤ.- + 1 ≡ applySign true (+ (q + 1))
  neg-minus-one q = sym (ℤₚ.neg-distrib-+ (+ q) (+ 1))

  -- The integer that roundToIntegral gives, read back by `as i32`.
  rti-toI32 : ∀ md x (P : Parts x) → let open Parts P; k = intRound md s q r in
              k ≤ q + 1 → (r ≡ 0 → k ≡ q) → toI32 (roundToIntegral md x) ≡ applySign s (+ k)
  rti-toI32 md x (parts-of s s′ s₁ V q r kx repV q≡ r≡ V≡ t0≡ ky kf shape) k≤ k≡ =
    trans (cong (λ c → toI32K (classify (roundToIntegralK md x c))) kx)
      (trans (cong₂ (λ a b → toI32K (classify (round s (intRound md s a b * U) 149))) (sym q≡) (sym r≡))
        (trans (cong toI32K (round-exact s (k * U) (round-int-repr repV k k≤′ k≡′)))
               (cong (λ n → applySign s (+ n)) (kU/U k))))
    where
      k = intRound md s q r
      k≤′ : k ≤ V /2^ 149 + 1
      k≤′ = subst (λ n → k ≤ n + 1) q≡ k≤
      k≡′ : V %2^ 149 ≡ 0 → k ≡ V /2^ 149
      k≡′ e = trans (k≡ (trans r≡ e)) q≡

  rna≤ : ∀ s q r → intRound RNA s q r ≤ q + 1
  rna≤ s q r = ℕₚ.+-monoʳ-≤ q (bit≤1 (U ≤ᵇ 2 * r))

  rna≡ : ∀ s q r → r ≡ 0 → intRound RNA s q r ≡ q
  rna≡ s q .0 refl = trans (cong (λ b → q + bitN b) U≤ᵇ0) (ℕₚ.+-identityʳ q)

  rtn≤ : ∀ s q r → intRound RTN s q r ≤ q + 1
  rtn≤ false q r = ℕₚ.m≤m+n q 1
  rtn≤ true  q r = ℕₚ.+-monoʳ-≤ q (bit≤1 (0 <ᵇ r))

  rtn≡ : ∀ s q r → r ≡ 0 → intRound RTN s q r ≡ q
  rtn≡ false q .0 refl = refl
  rtn≡ true  q .0 refl = ℕₚ.+-identityʳ q

-- ---------------------------------------------------------------------------------------------
-- nint = round half away (util.rs:21)

private
  GE LE : Kind → Bool
  GE k = not (isNaNK k) ∧ not (ltK k (classify half))
  LE k = not (isNaNK k) ∧ not (ltK (classify (neg half)) k)

  nint-shape : ∀ {s s′ s₁ q r} → Shape s s′ s₁ q r →
               nintB (applySign s (+ q)) (GE (fin s₁ r)) (LE (fin s₁ r)) ≡ applySign s (+ (q + bitN (not (r <ᵇ H))))
  nint-shape {q = q} {r} pos with r <ᵇ H
  ... | true  = cong +_ (sym (ℕₚ.+-identityʳ q))
  ... | false = refl
  nint-shape {q = q} (neg-int _) = cong (λ n → applySign true (+ n)) (sym (ℕₚ.+-identityʳ q))
  nint-shape {q = q} {suc r} (neg-frac _) with suc r <ᵇ H
  ... | true  = cong (λ n → applySign true (+ n)) (sym (ℕₚ.+-identityʳ q))
  ... | false = neg-minus-one q
  nint-shape {r = r} neg-small rewrite snz-H r with r <ᵇ H
  ... | true  = refl
  ... | false = refl

nint-round-half-away : ∀ x → inI32 x ≡ true → nint x ≡ toI32 (roundToIntegral RNA x)
nint-round-half-away x p with parts x p
... | P@(parts-of s s′ s₁ V q r kx repV q≡ r≡ V≡ t0≡ ky kf shape) =
  trans (cong (λ t → nintB t (ge (frac-of x) half) (le (frac-of x) (neg half))) t0≡)
    (trans (cong₂ (nintB (applySign s (+ q))) (cong GE kf) (cong LE kf))
      (trans (nint-shape shape)
        (sym (trans (rti-toI32 RNA x P (rna≤ s q r) (rna≡ s q r))
                    (cong (λ b → applySign s (+ (q + bitN b)))  (half-bit r))))))

-- nint_frac_exact (util.rs:24): t as f32 + frac gives x back.
private
  FEQ : Kind → Kind → Bool
  FEQ a b = not (isNaNK a) ∧ not (isNaNK b) ∧ not (ltK a b) ∧ not (ltK b a)

  feq-refl : ∀ s V → FEQ (fin s V) (fin s V) ≡ true
  feq-refl false V rewrite n<ᵇn V = refl
  feq-refl true  V rewrite n<ᵇn V = refl

  sum-kind : ∀ {s s′ s₁ V q r} → Shape s s′ s₁ q r → Repr V → V ≡ r + q * U →
             FEQ (classify (addFin s′ (q * U) s₁ r)) (fin s V) ≡ true
  sum-kind {V = V} {q} {r} pos rp V≡ =
    trans (cong (λ k → FEQ k (fin false V))
                (trans (round-exact false (q * U + r) (subst Repr V≡′ rp)) (cong (fin false) (sym V≡′))))
          (feq-refl false V)
    where V≡′ = trans V≡ (ℕₚ.+-comm r (q * U))
  sum-kind {V = V} {q} {suc r} (neg-frac _) rp V≡ =
    trans (cong (λ k → FEQ k (fin true V))
                (trans (round-exact true (q * U + suc r) (subst Repr V≡′ rp)) (cong (fin true) (sym V≡′))))
          (feq-refl true V)
    where V≡′ = trans V≡ (ℕₚ.+-comm (suc r) (q * U))
  sum-kind {V = V} {q} (neg-int q>0) rp V≡ =
    trans (cong (λ k → FEQ k (fin true V))
                (trans (cancel-gt true (q * U) false 0 (qU>0 q q>0) (subst Repr V≡ rp)) (cong (fin true) (sym V≡))))
          (feq-refl true V)
  sum-kind {V = V} {r = zero} neg-small rp V≡ rewrite V≡ = refl
  sum-kind {V = V} {r = suc r} neg-small rp V≡ =
    trans (cong (λ k → FEQ k (fin true V))
                (trans (round-exact true (suc r) (subst Repr V≡′ rp)) (cong (fin true) (sym V≡′))))
          (feq-refl true V)
    where V≡′ = trans V≡ (ℕₚ.+-identityʳ (suc r))

nint-frac-exact : ∀ x → inI32 x ≡ true → feq (add (fromI32 (toI32 x)) (frac-of x)) x ≡ true
nint-frac-exact x p with parts x p
... | parts-of s s′ s₁ V q r kx repV q≡ r≡ V≡ t0≡ ky kf shape =
  trans (cong₂ FEQ (cong₂ (λ a b → classify (addK y f a b)) ky kf) kx) (sum-kind shape repV V≡)
  where
    y = fromI32 (toI32 x)
    f = frac-of x

-- ---------------------------------------------------------------------------------------------
-- floor = round down (util.rs:34)

private
  floor-shape : ∀ {s s′ s₁ V q r} → Shape s s′ s₁ q r → V ≡ r + q * U →
                floorB (applySign s (+ q)) (ltSM s V s′ (q * U)) ≡ applySign s (+ intRound RTN s q r)
  floor-shape {V = V} {q} {r} pos V≡ =
    cong (floorB (+ q)) (<ᵇ-false (subst (q * U ≤_) (sym V≡) (ℕₚ.m≤n+m (q * U) r)))
  floor-shape {V = V} {q} (neg-int _) V≡ =
    trans (cong (floorB (applySign true (+ q))) (trans (cong (q * U <ᵇ_) V≡) (n<ᵇn (q * U))))
          (cong (λ n → applySign true (+ n)) (sym (ℕₚ.+-identityʳ q)))
  floor-shape {V = V} {q} {suc r} (neg-frac _) V≡ =
    trans (cong (floorB (applySign true (+ q))) (<ᵇ-true (subst (q * U <_) (sym V≡) (ℕₚ.m<n+m (q * U) (s≤s z≤n)))))
          (neg-minus-one q)
  floor-shape {V = V} {r = r} neg-small V≡ rewrite snz-0 V | trans V≡ (ℕₚ.+-identityʳ r) with r
  ... | zero  = refl
  ... | suc _ = refl

floor-round-down : ∀ x → inI32 x ≡ true → floor′ x ≡ toI32 (roundToIntegral RTN x)
floor-round-down x p with parts x p
... | P@(parts-of s s′ s₁ V q r kx repV q≡ r≡ V≡ t0≡ ky kf shape) =
  trans (cong (λ t → floorB t (gt (fromI32 (toI32 x)) x)) t0≡)
    (trans (cong (floorB (applySign s (+ q))) (cong₂ ltK kx ky))
      (trans (floor-shape shape V≡) (sym (rti-toI32 RTN x P (rtn≤ s q r) (rtn≡ s q r)))))

-- ---------------------------------------------------------------------------------------------
-- sign = SIGN(A, B) (util.rs:41)

private
  and-ones : ∀ {n} (v : Vec Bool n) → zipWith _∧_ v (replicate n true) ≡ v
  and-ones []            = refl
  and-ones (true  ∷ v)   = cong (true ∷_) (and-ones v)
  and-ones (false ∷ v)   = cong (false ∷_) (and-ones v)

  and-zeros : ∀ {n} (v : Vec Bool n) → zipWith _∧_ v (replicate n false) ≡ replicate n false
  and-zeros []           = refl
  and-zeros (true  ∷ v)  = cong (false ∷_) (and-zeros v)
  and-zeros (false ∷ v)  = cong (false ∷_) (and-zeros v)

  or-zeros : ∀ {n} (v : Vec Bool n) → zipWith _∨_ v (replicate n false) ≡ v
  or-zeros []            = refl
  or-zeros (true  ∷ v)   = cong (true ∷_) (or-zeros v)
  or-zeros (false ∷ v)   = cong (false ∷_) (or-zeros v)

  -- The masks, read from their hexadecimal values.
  mask-magnitude : fromℕ 32 0x7fffffff ≡ false ∷ replicate 31 true
  mask-magnitude = refl

  mask-sign : fromℕ 32 0x80000000 ≡ true ∷ replicate 31 false
  mask-sign = refl

  head-bit : ∀ a b → (a ∧ false) ∨ (b ∧ true) ≡ b
  head-bit true  true  = refl
  head-bit true  false = refl
  head-bit false true  = refl
  head-bit false false = refl

-- The bit copy: the 31 low bits of a and the sign bit of b.
signBits≡ : ∀ a b → signBits a b ≡ sign b ∷ (exp a ++ frac a)
signBits≡ (float sa ea fa) (float sb eb fb) =
  trans (cong₂ (λ m₁ m₂ → (bits (float sa ea fa) & m₁) ∣ (bits (float sb eb fb) & m₂)) mask-magnitude mask-sign)
        (cong₂ _∷_ (head-bit sa sb)
               (trans (cong₂ (zipWith _∨_) (and-ones (ea ++ fa)) (and-zeros (eb ++ fb))) (or-zeros (ea ++ fa))))

private
  isNeg-kindB : ∀ s E F b c → isNaNK (kindB s E F b c) ≡ false → isNegativeK (kindB s E F b c) ≡ s
  isNeg-kindB s E F true  true  _ = refl
  isNeg-kindB s E F true  false ()
  isNeg-kindB s E F false c     _ = refl

-- For a float that is not NaN, fpIsNegative is the sign bit.
isNegative≡sign : ∀ b → isNaN b ≡ false → isNegative b ≡ sign b
isNegative≡sign (float s e f) = isNeg-kindB s (toℕ e) (toℕ f) _ _

private
  fsign-bits : ∀ a s → fsignB a s ≡ float s (exp a) (frac a)
  fsign-bits a true  = refl
  fsign-bits a false = refl

sign-SIGN : ∀ a b → isNaN a ≡ false → isNaN b ≡ false → signBits a b ≡ bits (fsign a b)
sign-SIGN a b _ b-nan =
  trans (signBits≡ a b) (sym (cong bits (trans (cong (fsignB a) (isNegative≡sign b b-nan)) (fsign-bits a (sign b)))))

-- sign_negative_zero: SIGN(a, -0.) is -|a|, as gfortran gives.
private
  pos-kindB : ∀ s E F b c → ltK (fin false 0) (kindB s E F b c) ≡ true → s ≡ false
  pos-kindB false E F true  true  _ = refl
  pos-kindB true  E F true  true  ()
  pos-kindB s     E F true  false ()
  pos-kindB false E F false c     _ = refl
  pos-kindB true  E F false c     ()

  zero-not-nan : ∀ k → isZeroK k ≡ true → isNaNK k ≡ false
  zero-not-nan (fin s zero) _ = refl

positive-sign : ∀ a → gt a zeroF ≡ true → sign a ≡ false
positive-sign (float s e f) = pos-kindB s (toℕ e) (toℕ f) (toℕ e ℕ.≡ᵇ 255) (toℕ f ℕ.≡ᵇ 0)

sign-negative-zero : ∀ a b → isZero b ≡ true → isNegative b ≡ true → isNaN a ≡ false → gt a zeroF ≡ true →
                     bits (neg a) ≡ signBits a b
sign-negative-zero a b b-zero b-neg _ a-pos =
  sym (trans (signBits≡ a b)
             (cong (_∷ (exp a ++ frac a))
                   (trans (sym (trans (sym b-neg) (isNegative≡sign b (zero-not-nan (classify b) b-zero))))
                          (cong not (sym (positive-sign a a-pos))))))
