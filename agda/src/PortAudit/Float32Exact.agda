{-# OPTIONS --safe --without-K #-}

-- Lemmas of the f32 model (`PortAudit.Float32`). The main one is `round-exact`: a magnitude that
-- an f32 can hold exactly rounds to itself. Such a magnitude is N * 2^j units of 2^-149, with a
-- significand N < 2^24 and j ≤ 253 (`Repr`). Every finite float has one (`classify-repr`), and
-- so do the integer and fraction parts that `nint` and `floor` compute
-- (`PortAudit.Intrinsics`).
module PortAudit.Float32Exact where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; T)
open import Data.Bool.Properties using (T-≡; T-not-≡)
open import Data.Maybe using (just)
open import Data.Nat as ℕ
  using (ℕ; zero; suc; _+_; _*_; _∸_; _^_; _<ᵇ_; _≤ᵇ_; _≡ᵇ_; _≤_; _<_; z≤n; s≤s; NonZero)
import Data.Nat.Properties as ℕₚ
open import Data.Nat.DivMod
  using (m*n/n≡m; m*n%n≡0; m≡m%n+[m/n]*n; m%n≤m; m<n*o⇒m/o<n; m%n*o≡m*o%[n*o]; %-congʳ)
open import Data.Nat.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:*_; con)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Vec using (Vec; []; _∷_)
open import Function using (Equivalence)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)
open import Relation.Nullary using (¬_; contradiction; yes; no)

open import PortAudit.Float32

-- ---------------------------------------------------------------------------------------------
-- Booleans of ℕ

T⇒≡ : ∀ {b} → T b → b ≡ true
T⇒≡ = Equivalence.to T-≡

≡⇒T : ∀ {b} → b ≡ true → T b
≡⇒T = Equivalence.from T-≡

<ᵇ-true : ∀ {m n} → m < n → (m <ᵇ n) ≡ true
<ᵇ-true m<n = T⇒≡ (ℕₚ.<⇒<ᵇ m<n)

<ᵇ-false : ∀ {m n} → n ≤ m → (m <ᵇ n) ≡ false
<ᵇ-false {m} {n} n≤m with m <ᵇ n in eq
... | false = refl
... | true  = contradiction n≤m (ℕₚ.<⇒≱ (ℕₚ.<ᵇ⇒< m n (≡⇒T eq)))

<ᵇ⇒< : ∀ {m n} → (m <ᵇ n) ≡ true → m < n
<ᵇ⇒< {m} {n} eq = ℕₚ.<ᵇ⇒< m n (≡⇒T eq)

<ᵇ⇒≥ : ∀ {m n} → (m <ᵇ n) ≡ false → n ≤ m
<ᵇ⇒≥ {m} {n} eq = ℕₚ.≮⇒≥ (λ m<n → case (trans (sym (<ᵇ-true m<n)) eq))
  where case : true ≡ false → _
        case ()

≤ᵇ-true : ∀ {m n} → m ≤ n → (m ≤ᵇ n) ≡ true
≤ᵇ-true m≤n = T⇒≡ (ℕₚ.≤⇒≤ᵇ m≤n)

≤ᵇ-false : ∀ {m n} → n < m → (m ≤ᵇ n) ≡ false
≤ᵇ-false {m} {n} n<m with m ≤ᵇ n in eq
... | false = refl
... | true  = contradiction (ℕₚ.≤ᵇ⇒≤ m n (≡⇒T eq)) (ℕₚ.<⇒≱ n<m)

≤ᵇ⇒≤ : ∀ {m n} → (m ≤ᵇ n) ≡ true → m ≤ n
≤ᵇ⇒≤ {m} {n} eq = ℕₚ.≤ᵇ⇒≤ m n (≡⇒T eq)

≤ᵇ⇒> : ∀ {m n} → (m ≤ᵇ n) ≡ false → n < m
≤ᵇ⇒> {m} {n} eq = ℕₚ.≰⇒> (λ m≤n → case (trans (sym (≤ᵇ-true m≤n)) eq))
  where case : true ≡ false → _
        case ()

≡ᵇ-false : ∀ {m n} → m ≢ n → (m ≡ᵇ n) ≡ false
≡ᵇ-false {m} {n} m≢n with m ≡ᵇ n in eq
... | false = refl
... | true  = contradiction (ℕₚ.≡ᵇ⇒≡ m n (≡⇒T eq)) m≢n

-- ---------------------------------------------------------------------------------------------
-- Powers of two

2^>0 : ∀ k → 0 < 2 ^ k
2^>0 k = ℕₚ.m^n>0 2 k

nz : ∀ k → NonZero (2 ^ k)
nz k = ℕₚ.m^n≢0 2 k

2^≢ᵇ0 : ∀ k → (2 ^ k ≡ᵇ 0) ≡ false
2^≢ᵇ0 k = ≡ᵇ-false (λ eq → ℕₚ.<⇒≢ (2^>0 k) (sym eq))

-- ---------------------------------------------------------------------------------------------
-- Bit vectors

private
  two-pow : ∀ n → 2 ^ suc n ≡ 2 ^ n + 2 ^ n
  two-pow n = cong (2 ^ n +_) (ℕₚ.+-identityʳ (2 ^ n))

toℕ-fromℕ : ∀ n x → x < 2 ^ n → toℕ (fromℕ n x) ≡ x
toℕ-fromℕ zero    zero    _ = refl
toℕ-fromℕ zero    (suc x) (s≤s ())
toℕ-fromℕ (suc n) x x<2^sn with 2 ^ n ≤ᵇ x in eq
... | true  = trans (cong (1 * 2 ^ n +_) (toℕ-fromℕ n (x ∸ 2 ^ n) rest<))
                    (trans (cong (_+ (x ∸ 2 ^ n)) (ℕₚ.*-identityˡ (2 ^ n))) (ℕₚ.m+[n∸m]≡n 2^n≤x))
  where
    2^n≤x : 2 ^ n ≤ x
    2^n≤x = ≤ᵇ⇒≤ eq
    rest< : x ∸ 2 ^ n < 2 ^ n
    rest< = ℕₚ.+-cancelˡ-< (2 ^ n) _ _
              (subst (_< 2 ^ n + 2 ^ n) (sym (ℕₚ.m+[n∸m]≡n 2^n≤x)) (subst (x <_) (two-pow n) x<2^sn))
... | false = toℕ-fromℕ n x (≤ᵇ⇒> eq)

toℕ-bound : ∀ {n} (v : Vec Bool n) → toℕ v < 2 ^ n
toℕ-bound [] = s≤s z≤n
toℕ-bound {suc n} (b ∷ v) =
  subst (bitN b * 2 ^ n + toℕ v <_) (sym (two-pow n)) (ℕₚ.+-mono-≤-< (bit≤ b) (toℕ-bound v))
  where
    bit≤ : ∀ b → bitN b * 2 ^ n ≤ 2 ^ n
    bit≤ true  = ℕₚ.≤-reflexive (ℕₚ.*-identityˡ (2 ^ n))
    bit≤ false = z≤n

-- ---------------------------------------------------------------------------------------------
-- What a constructed float means

fin-injective : ∀ {s t m n} → fin s m ≡ fin t n → s ≡ t × m ≡ n
fin-injective refl = refl , refl

kind-mk : ∀ s e m → e < 255 → m < 2 ^ 23 → classify (mk s e m) ≡ fin s (magEF e m)
kind-mk s e m e<255 m<2^23 =
  trans (cong₂ (kindEF s) (toℕ-fromℕ 8 e (ℕₚ.m<n⇒m<1+n e<255)) (toℕ-fromℕ 23 m m<2^23))
        (cong (λ b → kindB s e m b (m ≡ᵇ 0)) (≡ᵇ-false (ℕₚ.<⇒≢ e<255)))

-- What the bits of a finite float say: its sign bit and a magnitude that has a significand.
record Repr (I : ℕ) : Set where
  constructor repr
  field
    N   : ℕ
    j   : ℕ
    N<  : N < 2 ^ 24
    j≤  : j ≤ 253
    I≡  : I ≡ N * 2 ^ j

private
  kindB-fin : ∀ s E F b c {t m} → (E ≡ᵇ 255) ≡ b → kindB s E F b c ≡ fin t m →
              E < 256 → F < 2 ^ 23 → s ≡ t × Repr m
  kindB-fin s E F true  true  _  () _ _
  kindB-fin s E F true  false _  () _ _
  kindB-fin s E F false c     eq refl E<256 F< = refl , mag-repr E (ℕₚ.≤∧≢⇒< (ℕₚ.≤-pred E<256) E≢)
    where
      E≢ : E ≢ 255
      E≢ E≡ = case (trans (sym (T⇒≡ (ℕₚ.≡⇒≡ᵇ E 255 E≡))) eq)
        where case : true ≡ false → _
              case ()
      mag-repr : ∀ E → E < 255 → Repr (magEF E F)
      mag-repr zero    _       = repr F 0 (ℕₚ.<-≤-trans F< (ℕₚ.m≤m+n (2 ^ 23) (2 ^ 23)))
                                      z≤n (sym (ℕₚ.*-identityʳ F))
      mag-repr (suc e) (s≤s e<254) = repr (F + 2 ^ 23) e (ℕₚ.+-monoˡ-< (2 ^ 23) F<) (ℕₚ.≤-pred e<254) refl

-- A finite float: its sign bit, and its magnitude as N * 2^j.
classify-fin : ∀ x {t m} → classify x ≡ fin t m → sign x ≡ t × Repr m
classify-fin (float s e f) eq = kindB-fin s (toℕ e) (toℕ f) _ _ refl eq (toℕ-bound e) (toℕ-bound f)

negK absK : Kind → Kind
negK nan       = nan
negK (inf s)   = inf (not s)
negK (fin s m) = fin (not s) m
absK nan       = nan
absK (inf s)   = inf false
absK (fin s m) = fin false m

private
  kindB-neg : ∀ s E F b c → kindB (not s) E F b c ≡ negK (kindB s E F b c)
  kindB-neg s E F true  true  = refl
  kindB-neg s E F true  false = refl
  kindB-neg s E F false c     = refl

  kindB-abs : ∀ s E F b c → kindB false E F b c ≡ absK (kindB s E F b c)
  kindB-abs s E F true  true  = refl
  kindB-abs s E F true  false = refl
  kindB-abs s E F false c     = refl

classify-neg : ∀ x → classify (neg x) ≡ negK (classify x)
classify-neg (float s e f) = kindB-neg s (toℕ e) (toℕ f) _ _

classify-abs : ∀ x → classify (abs x) ≡ absK (classify x)
classify-abs (float s e f) = kindB-abs s (toℕ e) (toℕ f) _ _

-- ---------------------------------------------------------------------------------------------
-- A magnitude with a significand rounds to itself

pick-lands : ∀ d f k n → d < f → (∀ i → i < d → 2 ^ (k + i) * 2 ^ 24 ≤ n) →
             n < 2 ^ (k + d) * 2 ^ 24 → pick f k n ≡ just (k + d)
pick-lands zero (suc f) k n _ _ n< =
  trans (cong (pickB f k n) (<ᵇ-true (subst (λ e → n < 2 ^ e * 2 ^ 24) (ℕₚ.+-identityʳ k) n<)))
        (cong just (sym (ℕₚ.+-identityʳ k)))
pick-lands (suc d) (suc f) k n (s≤s d<f) below n< =
  trans (cong (pickB f k n) (<ᵇ-false (subst (λ e → 2 ^ e * 2 ^ 24 ≤ n) (ℕₚ.+-identityʳ k)
                                                  (below 0 (s≤s z≤n)))))
        (trans (pick-lands d f (suc k) n d<f
                  (λ i i<d → subst (λ e → 2 ^ e * 2 ^ 24 ≤ n) (ℕₚ.+-suc k i) (below (suc i) (s≤s i<d)))
                  (subst (λ e → n < 2 ^ e * 2 ^ 24) (ℕₚ.+-suc k d) n<))
               (cong just (sym (ℕₚ.+-suc k d))))

private
  encodeB-fin : ∀ s d N b c → (N <ᵇ 2 ^ 23) ≡ b → (d <ᵇ 254) ≡ c → N < 2 ^ 24 →
                (d ≡ 0 ⊎ 2 ^ 23 ≤ N) → d < 254 → classify (encodeB s d N b c) ≡ fin s (N * 2 ^ d)
  encodeB-fin s d N true c eqb _ _ (inj₁ refl) _ =
    trans (kind-mk s 0 N (s≤s z≤n) (<ᵇ⇒< eqb)) (cong (fin s) (sym (ℕₚ.*-identityʳ N)))
  encodeB-fin s d N true c eqb _ _ (inj₂ 2^23≤N) _ = contradiction (<ᵇ⇒< eqb) (ℕₚ.≤⇒≯ 2^23≤N)
  encodeB-fin s d N false true eqb _ N< _ d<254 =
    trans (kind-mk s (suc d) (N ∸ 2 ^ 23) (s≤s d<254) frac<)
          (cong (λ x → fin s (x * 2 ^ d)) (ℕₚ.m∸n+n≡m 2^23≤N))
    where
      2^23≤N : 2 ^ 23 ≤ N
      2^23≤N = <ᵇ⇒≥ eqb
      frac< : N ∸ 2 ^ 23 < 2 ^ 23
      frac< = ℕₚ.+-cancelʳ-< (2 ^ 23) (N ∸ 2 ^ 23) (2 ^ 23) (subst (_< 2 ^ 23 + 2 ^ 23) (sym (ℕₚ.m∸n+n≡m 2^23≤N)) N<)
  encodeB-fin s d N false false _ eqc _ _ d<254 = contradiction d<254 (ℕₚ.≤⇒≯ (<ᵇ⇒≥ eqc))

  encode-fin : ∀ s d N → N < 2 ^ 24 → (d ≡ 0 ⊎ 2 ^ 23 ≤ N) → d < 254 →
               classify (encode s d N) ≡ fin s (N * 2 ^ d)
  encode-fin s d N = encodeB-fin s d N _ _ refl refl

  -- N * 2^j divided by 2^j: the quotient is N, the remainder 0, so nothing rounds.
  roundAt-exact : ∀ s N j → N < 2 ^ 24 → roundAt s (N * 2 ^ j) 0 (just j) ≡ encode s j N
  roundAt-exact s N j N< =
    trans (cong₂ (λ q r → finish s j (q + bitN (rneUp j q r))) (m*n/n≡m N (2 ^ j) {{nz j}}) (m*n%n≡0 N (2 ^ j) {{nz j}}))
      (trans (cong (λ b → finish s j (N + bitN (b ∧ odd N))) (2^≢ᵇ0 j))
        (trans (cong (finish s j) (ℕₚ.+-identityʳ N))
               (cong (finishB s j N) (≡ᵇ-false (ℕₚ.<⇒≢ N<)))))

  round-core : ∀ s N j → N < 2 ^ 24 → j ≤ 253 → (j ≡ 0 ⊎ 2 ^ 23 ≤ N) →
               classify (round s (N * 2 ^ j) 149) ≡ fin s (N * 2 ^ j)
  round-core s N j N< j≤ canon =
    trans (cong (λ p → classify (roundAt s (N * 2 ^ j) 0 p))
                (pick-lands j 255 0 (N * 2 ^ j) (ℕₚ.m<n⇒m<1+n j<254) below above))
          (trans (cong classify (roundAt-exact s N j N<)) (encode-fin s j N N< canon j<254))
    where
      j<254 : j < 254
      j<254 = s≤s j≤
      below′ : (j ≡ 0 ⊎ 2 ^ 23 ≤ N) → ∀ i → i < j → 2 ^ i * 2 ^ 24 ≤ N * 2 ^ j
      below′ (inj₁ refl) i ()
      below′ (inj₂ 2^23≤N) i i<j =
        subst (_≤ N * 2 ^ j) (solve 1 (λ x → (con 2 :* x) :* con (2 ^ 23) := x :* con (2 ^ 24)) refl (2 ^ i))
          (ℕₚ.≤-trans (ℕₚ.*-monoˡ-≤ (2 ^ 23) (ℕₚ.^-monoʳ-≤ 2 i<j))
            (subst (2 ^ j * 2 ^ 23 ≤_) (ℕₚ.*-comm (2 ^ j) N) (ℕₚ.*-monoʳ-≤ (2 ^ j) 2^23≤N)))
      below : ∀ i → i < j → 2 ^ i * 2 ^ 24 ≤ N * 2 ^ j
      below = below′ canon
      above : N * 2 ^ j < 2 ^ j * 2 ^ 24
      above = subst (_< 2 ^ j * 2 ^ 24) (ℕₚ.*-comm (2 ^ j) N) (ℕₚ.*-monoʳ-< (2 ^ j) {{nz j}} N<)

  round-norm : ∀ s N j → N < 2 ^ 24 → j ≤ 253 → classify (round s (N * 2 ^ j) 149) ≡ fin s (N * 2 ^ j)
  round-norm s N zero    N< _ = round-core s N 0 N< z≤n (inj₁ refl)
  round-norm s N (suc j) N< sj≤ with 2 ^ 23 ℕ.≤? N
  ... | yes 2^23≤N = round-core s N (suc j) N< sj≤ (inj₂ 2^23≤N)
  ... | no  N<2^23 =
    subst (λ n → classify (round s n 149) ≡ fin s n)
          (solve 2 (λ n x → (con 2 :* n) :* x := n :* (con 2 :* x)) refl N (2 ^ j))
          (round-norm s (2 * N) j (ℕₚ.*-monoʳ-< 2 (ℕₚ.≰⇒> N<2^23)) (ℕₚ.≤-trans (ℕₚ.n≤1+n j) sj≤))

-- A magnitude that has a significand rounds to itself, with the sign it was given.
round-exact : ∀ s I → Repr I → classify (round s I 149) ≡ fin s I
round-exact s I (repr N j N< j≤ refl) = round-norm s N j N< j≤

-- ---------------------------------------------------------------------------------------------
-- The integer part and the fraction of a finite float

-- V = q * 2^149 + r: the integer part q and the fraction r, in units of 2^-149.
private
  P : ℕ
  P = 2 ^ 149

V≡r+qP : ∀ V → V ≡ V %2^ 149 + V /2^ 149 * P
V≡r+qP V = m≡m%n+[m/n]*n V P {{nz 149}}

private
  149≤253 : 149 ≤ 253
  149≤253 = ℕₚ.≤ᵇ⇒≤ 149 253 _

  2^23<2^24 : ∀ {k} → k < 2 ^ 23 → k < 2 ^ 24
  2^23<2^24 k< = ℕₚ.<-≤-trans k< (ℕₚ.m≤m+n (2 ^ 23) (2 ^ 23))

  -- With j ≥ 149 the float is an integer: V = Q * 2^149.
  big-int : ∀ N j → 149 ≤ j → N * 2 ^ j ≡ (N * 2 ^ (j ∸ 149)) * P
  big-int N j 149≤j =
    trans (cong (λ e → N * 2 ^ e) (sym (ℕₚ.m∸n+n≡m 149≤j)))
          (trans (cong (N *_) (ℕₚ.^-distribˡ-+-* 2 (j ∸ 149) 149))
                 (sym (ℕₚ.*-assoc N (2 ^ (j ∸ 149)) P)))

  -- With j < 149 the integer part has at most 23 bits.
  small-q : ∀ N j → N < 2 ^ 24 → j < 149 → (N * 2 ^ j) /2^ 149 < 2 ^ 23
  small-q N j N< j<149 = m<n*o⇒m/o<n {n = 2 ^ 23} {o = P} {{nz 149}} V<
    where
      V< : N * 2 ^ j < 2 ^ 23 * P
      V< = subst (_< 2 ^ 23 * P) (ℕₚ.*-comm (2 ^ j) N)
             (ℕₚ.<-≤-trans (ℕₚ.*-monoʳ-< (2 ^ j) {{nz j}} N<)
                           (ℕₚ.*-monoˡ-≤ (2 ^ 24) (ℕₚ.^-monoʳ-≤ 2 (ℕₚ.≤-pred j<149))))

int-reprP : ∀ {V} → Repr V → Repr (V /2^ 149 * P)
int-reprP {V} r@(repr N j N< j≤ refl) with 149 ℕ.≤? j
... | yes 149≤j = subst Repr (trans (big-int N j 149≤j)
                                    (cong (_* P) (sym (trans (cong (_/2^ 149) (big-int N j 149≤j))
                                                             (m*n/n≡m (N * 2 ^ (j ∸ 149)) P {{nz 149}}))))) r
... | no  j<149 = repr (V /2^ 149) 149 (2^23<2^24 (small-q N j N< (ℕₚ.≰⇒> j<149))) 149≤253 refl

frac-repr : ∀ {V} → Repr V → Repr (V %2^ 149)
frac-repr {V} (repr N j N< j≤ refl) with 149 ℕ.≤? j
... | yes 149≤j = subst Repr (sym (trans (cong (_%2^ 149) (big-int N j 149≤j))
                                         (m*n%n≡0 (N * 2 ^ (j ∸ 149)) P {{nz 149}})))
                         (repr 0 0 (2^>0 24) z≤n refl)
... | no  j≮149 = subst Repr (sym V%P) (repr (N %2^ d) j (ℕₚ.≤-<-trans (m%n≤m N (2 ^ d) {{nz d}}) N<) j≤ refl)
  where
    j<149 = ℕₚ.≰⇒> j≮149
    d = 149 ∸ j
    P≡d+j : P ≡ 2 ^ d * 2 ^ j
    P≡d+j = trans (cong (2 ^_) (sym (ℕₚ.m∸n+n≡m (ℕₚ.<⇒≤ j<149)))) (ℕₚ.^-distribˡ-+-* 2 d j)
    V%P : (N * 2 ^ j) %2^ 149 ≡ (N %2^ d) * 2 ^ j
    V%P = trans (%-congʳ {{nz 149}} {{ℕₚ.m*n≢0 (2 ^ d) (2 ^ j) {{nz d}} {{nz j}}}} P≡d+j)
                (sym (m%n*o≡m*o%[n*o] N (2 ^ d) (2 ^ j) {{nz d}} {{ℕₚ.m*n≢0 (2 ^ d) (2 ^ j) {{nz d}} {{nz j}}}}))

-- The integer that roundToIntegral gives: at most one above the integer part, and equal to it
-- when the float is an integer.
round-int-reprP : ∀ {V} → Repr V → ∀ k → k ≤ V /2^ 149 + 1 → (V %2^ 149 ≡ 0 → k ≡ V /2^ 149) → Repr (k * P)
round-int-reprP {V} rp@(repr N j N< j≤ refl) k k≤ k≡ with 149 ℕ.≤? j
... | yes 149≤j = subst (λ k → Repr (k * P)) (sym (k≡ r≡0)) (int-reprP rp)
  where
    r≡0 : V %2^ 149 ≡ 0
    r≡0 = trans (cong (_%2^ 149) (big-int N j 149≤j)) (m*n%n≡0 (N * 2 ^ (j ∸ 149)) P {{nz 149}})
... | no  j≮149 = repr k 149 k< 149≤253 refl
  where
    k< : k < 2 ^ 24
    k< = ℕₚ.≤-<-trans (ℕₚ.≤-trans k≤ (subst (_≤ 2 ^ 23) (ℕₚ.+-comm 1 (V /2^ 149)) (small-q N j N< (ℕₚ.≰⇒> j≮149))))
                      (ℕₚ.m<m+n (2 ^ 23) (2^>0 23))


V≡r+qU : ∀ V → V ≡ V %2^ 149 + V /2^ 149 * U
V≡r+qU V = subst (λ u → V ≡ V %2^ 149 + V /2^ 149 * u) (sym U≡) (V≡r+qP V)

int-repr : ∀ {V} → Repr V → Repr (V /2^ 149 * U)
int-repr {V} rp = subst (λ u → Repr (V /2^ 149 * u)) (sym U≡) (int-reprP rp)

round-int-repr : ∀ {V} → Repr V → ∀ k → k ≤ V /2^ 149 + 1 → (V %2^ 149 ≡ 0 → k ≡ V /2^ 149) → Repr (k * U)
round-int-repr {V} rp k k≤ k≡ = subst (λ u → Repr (k * u)) (sym U≡) (round-int-reprP rp k k≤ k≡)

-- (k * U) / 2^149 = k.
kU/U : ∀ k → (k * U) /2^ 149 ≡ k
kU/U k = subst (λ u → (k * u) /2^ 149 ≡ k) (sym U≡) (m*n/n≡m k (2 ^ 149) {{nz 149}})

-- ---------------------------------------------------------------------------------------------
-- Sums of opposite signs

n<ᵇn : ∀ n → (n <ᵇ n) ≡ false
n<ᵇn n = <ᵇ-false {n} {n} ℕₚ.≤-refl

cancel-gt : ∀ s m t n → n < m → Repr (m ∸ n) →
            classify (cancelB s m t n (n <ᵇ m) (m <ᵇ n)) ≡ fin s (m ∸ n)
cancel-gt s m t n n<m rp =
  trans (cong₂ (λ a b → classify (cancelB s m t n a b)) (<ᵇ-true n<m) (<ᵇ-false (ℕₚ.<⇒≤ n<m)))
        (round-exact s (m ∸ n) rp)

cancel-eq : ∀ s m t n → m ≡ n → classify (cancelB s m t n (n <ᵇ m) (m <ᵇ n)) ≡ fin false 0
cancel-eq s m t .m refl = cong₂ (λ a b → classify (cancelB s m t m a b)) (n<ᵇn m) (n<ᵇn m)
