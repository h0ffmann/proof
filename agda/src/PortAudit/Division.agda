{-# OPTIONS --safe --without-K #-}

-- Group D of the port audit of chaceon (`z3-scala/src/main/scala/portaudit/domain/Chaceon.scala`,
-- `just port-audit`): the division rewrite of rust/tools/spirv_exact/src/main.rs:3-7 at the
-- commit that `Chaceon.scala` pins. An f32 division becomes an f64 division rounded to f32,
-- because Vulkan allows 2.5 ULP in OpFDiv. The names follow Z3, with `-` for `_`.
--
-- a = A * 2^ea and b = B * 2^eb, with 24-bit significands A and B. The quotient is q = A / B,
-- and its f32 midpoints are m = M / 2^t, M odd in [2^24, 2^25), t = 24 or 25.
--
-- Z3 checks the integer facts over 100-bit vectors for t = 24 and t = 25. Agda proves them for
-- every t, A, B and M over ℕ (`no-tie`, `margin`) and then reads them at Z3's ranges. Z3's
-- counterexamples are witnesses that Agda checks by computation. The rounding facts are proved
-- over ℚ for every error bound δ and ε that meets two inequalities (`same-side`), and then read
-- at Z3's bounds, 2^-49 and 5/2 * 2^-52.
module PortAudit.Division where

open import Data.Bool using (Bool; true; false; T; if_then_else_)
open import Data.Empty using (⊥)
open import Data.Integer using (+_)
open import Data.Nat as ℕ
  using (ℕ; zero; suc; _^_; _≤_; _<_; _≤ᵇ_; _<ᵇ_; _≡ᵇ_; z≤n; s≤s; NonZero; ∣_-_∣; _%_)
import Data.Nat.Properties as ℕₚ
open import Data.Nat.DivMod using (m*n%n≡0; [m+kn]%n≡m%n)
open import Data.Nat.Solver using (module +-*-Solver)
open import Data.Product using (Σ; ∃; _×_; _,_; proj₁; proj₂)
open import Data.Rational as ℚ using (ℚ; 0ℚ; 1ℚ; _/_)
import Data.Rational.Properties as ℚₚ
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Function using (_⇔_; mk⇔)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; subst)
open import Relation.Nullary using (¬_; contradiction)
open import Relation.Nullary.Decidable using (from-yes)

-- ---------------------------------------------------------------------------------------------
-- Parity

Odd : ℕ → Set
Odd n = ∃ λ k → n ≡ suc (2 ℕ.* k)

private
  open +-*-Solver using (solve; _:=_; _:+_; _:*_; con)

  parity : ∀ n → ∃ λ k → n ≡ 2 ℕ.* k ⊎ n ≡ suc (2 ℕ.* k)
  parity zero = 0 , inj₁ refl
  parity (suc n) with parity n
  ... | k , inj₁ n≡ = k , inj₂ (cong suc n≡)
  ... | k , inj₂ n≡ = suc k , inj₁ (trans (cong suc n≡)
                                    (solve 1 (λ k → con 2 :+ con 2 :* k := con 2 :* (con 1 :+ k)) refl k))

  even≢odd : ∀ a b → 2 ℕ.* a ≢ suc (2 ℕ.* b)
  even≢odd a b eq = 0≢1 (trans (sym (even%2 a)) (trans (cong (_% 2) eq) (odd%2 b)))
    where
    0≢1 : 0 ≢ 1
    0≢1 ()
    even%2 : ∀ a → (2 ℕ.* a) % 2 ≡ 0
    even%2 a = trans (cong (_% 2) (ℕₚ.*-comm 2 a)) (m*n%n≡0 a 2)
    odd%2 : ∀ b → suc (2 ℕ.* b) % 2 ≡ 1
    odd%2 b = trans (cong (λ x → suc x % 2) (ℕₚ.*-comm 2 b)) ([m+kn]%n≡m%n 1 b 2)

-- ---------------------------------------------------------------------------------------------
-- no_tie: a quotient of two significands is never an f32 midpoint, A * 2^t ≢ M * B.

-- For every t, every odd M and every 0 < B < 2^t. Z3 checks t = 24 and t = 25.
no-tie : ∀ t A B M → Odd M → 0 < B → B < 2 ^ t → A ℕ.* 2 ^ t ≢ M ℕ.* B
no-tie zero    A B M _ 0<B B<1 _ = ℕₚ.<-irrefl refl (ℕₚ.<-≤-trans 0<B (ℕₚ.≤-pred B<1))
  where open import Data.Nat using () -- 0 < B ≤ 0
no-tie (suc t) A B M (m , M≡) 0<B B<2t eq with parity B
... | b , inj₂ B≡ = even≢odd (A ℕ.* 2 ^ t) (m ℕ.+ b ℕ.+ 2 ℕ.* m ℕ.* b)
      (trans (solve 2 (λ a p → con 2 :* (a :* p) := a :* (con 2 :* p)) refl A (2 ^ t))
      (trans eq (trans (cong₂′ ℕ._*_ M≡ B≡)
             (solve 2 (λ m b → (con 1 :+ con 2 :* m) :* (con 1 :+ con 2 :* b)
                               := con 1 :+ con 2 :* (m :+ b :+ con 2 :* m :* b)) refl m b))))
  where open import Relation.Binary.PropositionalEquality using () renaming (cong₂ to cong₂′)
... | b , inj₁ B≡ = no-tie t A b M (m , M≡) 0<b b<2t eq′
  where
  0<b : 0 < b
  0<b = ℕₚ.n≢0⇒n>0 λ b≡0 → ℕₚ.<-irrefl (sym (trans B≡ (cong (2 ℕ.*_) b≡0))) 0<B
  b<2t : b < 2 ^ t
  b<2t = ℕₚ.*-cancelˡ-< 2 b (2 ^ t) (subst (ℕ._< 2 ℕ.* 2 ^ t) B≡ B<2t)
  eq′ : A ℕ.* 2 ^ t ≡ M ℕ.* b
  eq′ = ℕₚ.*-cancelˡ-≡ (A ℕ.* 2 ^ t) (M ℕ.* b) 2
          (trans (solve 2 (λ a p → con 2 :* (a :* p) := a :* (con 2 :* p)) refl A (2 ^ t))
          (trans eq (trans (cong (M ℕ.*_) B≡)
                 (solve 2 (λ m b → m :* (con 2 :* b) := con 2 :* (m :* b)) refl M b))))

-- The distance of two naturals as Z3 writes it, ite(lhs >= rhs, lhs - rhs, rhs - lhs). It
-- computes with the built-in comparison and subtraction, so a witness on 50-bit numbers is fast.
gap : ℕ → ℕ → ℕ
gap lhs rhs = if rhs ≤ᵇ lhs then lhs ℕ.∸ rhs else rhs ℕ.∸ lhs

gap≡0⇒≡ : ∀ lhs rhs → gap lhs rhs ≡ 0 → lhs ≡ rhs
gap≡0⇒≡ lhs rhs g with rhs ≤ᵇ lhs in eq
... | true  = ℕₚ.≤-antisym (ℕₚ.m∸n≡0⇒m≤n g) (ℕₚ.≤ᵇ⇒≤ rhs lhs (subst T (sym eq) _))
... | false = contradiction (subst T eq (ℕₚ.≤⇒≤ᵇ (ℕₚ.m∸n≡0⇒m≤n {rhs} {lhs} g))) λ ()

-- margin: the distance from q to a midpoint is at least m / 2^k when M * B < 2^k. Dividing by
-- B * 2^t, |q - m| ≥ m / 2^k is 2^k * |A 2^t - M B| ≥ M B.
margin : ∀ t k A B M → Odd M → 0 < B → B < 2 ^ t → M ℕ.* B < 2 ^ k →
  M ℕ.* B ≤ 2 ^ k ℕ.* gap (A ℕ.* 2 ^ t) (M ℕ.* B)
margin t k A B M odd 0<B B<2t MB<2k =
  ℕₚ.≤-trans (ℕₚ.<⇒≤ MB<2k)
    (subst (ℕ._≤ 2 ^ k ℕ.* d) (ℕₚ.*-identityʳ (2 ^ k))
      (ℕₚ.*-monoʳ-≤ (2 ^ k) (ℕₚ.n≢0⇒n>0 (λ d≡0 →
        no-tie t A B M odd 0<B B<2t (gap≡0⇒≡ (A ℕ.* 2 ^ t) (M ℕ.* B) d≡0)))))
  where d = gap (A ℕ.* 2 ^ t) (M ℕ.* B)

-- ---------------------------------------------------------------------------------------------
-- The two statements at Z3's ranges: A, B in [2^23, 2^24), M odd in [2^24, 2^25).

Significand : ℕ → Set
Significand A = 2 ^ 23 ≤ A × A < 2 ^ 24

Midpoint : ℕ → Set
Midpoint M = 2 ^ 24 ≤ M × M < 2 ^ 25 × Odd M

private
  B>0 : ∀ {B} → Significand B → 0 < B
  B>0 (lo , _) = ℕₚ.<-≤-trans (ℕ.>-nonZero⁻¹ (2 ^ 23) {{ℕₚ.m^n≢0 2 23}}) lo

  B<2^t : ∀ {B} t → 24 ≤ t → Significand B → B < 2 ^ t
  B<2^t t 24≤t (_ , hi) = ℕₚ.<-≤-trans hi (ℕₚ.^-monoʳ-≤ 2 24≤t)

no-tie-24 : ∀ A B M → Significand A → Significand B → Midpoint M → A ℕ.* 2 ^ 24 ≢ M ℕ.* B
no-tie-24 A B M _ sB (_ , _ , odd) = no-tie 24 A B M odd (B>0 sB) (B<2^t 24 ℕₚ.≤-refl sB)

no-tie-25 : ∀ A B M → Significand A → Significand B → Midpoint M → A ℕ.* 2 ^ 25 ≢ M ℕ.* B
no-tie-25 A B M _ sB (_ , _ , odd) = no-tie 25 A B M odd (B>0 sB) (B<2^t 25 (ℕₚ.n≤1+n 24) sB)

-- M * B < 2^25 * 2^24 = 2^49.
private
  MB<2^49 : ∀ {B M : ℕ} → Significand B → Midpoint M → M ℕ.* B < 2 ^ 49
  MB<2^49 {B} {M} (_ , B<) (_ , M< , _) =
    subst (M ℕ.* B ℕ.<_) (sym (ℕₚ.^-distribˡ-+-* 2 25 24)) (ℕₚ.*-mono-< M< B<)

margin-24 : ∀ A B M → Significand A → Significand B → Midpoint M →
  M ℕ.* B ≤ 2 ^ 49 ℕ.* gap (A ℕ.* 2 ^ 24) (M ℕ.* B)
margin-24 A B M _ sB sM@(_ , _ , odd) =
  margin 24 49 A B M odd (B>0 sB) (B<2^t 24 ℕₚ.≤-refl sB) (MB<2^49 sB sM)

margin-25 : ∀ A B M → Significand A → Significand B → Midpoint M →
  M ℕ.* B ≤ 2 ^ 49 ℕ.* gap (A ℕ.* 2 ^ 25) (M ℕ.* B)
margin-25 A B M _ sB sM@(_ , _ , odd) =
  margin 25 49 A B M odd (B>0 sB) (B<2^t 25 (ℕₚ.n≤1+n 24) sB) (MB<2^49 sB sM)

-- margin_2^48_fails (t = 25), as a witness: the margin 2^-49 cannot be doubled. The bounds are
-- comparisons that Agda computes on the numbers (`_<ᵇ_` and `_≤ᵇ_` of ℕ, turned into proofs by
-- `≤ᵇ⇒≤` and `<ᵇ⇒<`). Here A * 2^25 = M * B + 1.
margin-2^48-fails : let A = 13981011 ; B = 16777213 ; M = 27962027 in
  Significand A × Significand B × Midpoint M ×
  ¬ (M ℕ.* B ≤ 2 ^ 48 ℕ.* gap (A ℕ.* 2 ^ 25) (M ℕ.* B))
margin-2^48-fails =
  (b≤ (2 ^ 23) A _ , b< A (2 ^ 24) _) , (b≤ (2 ^ 23) B _ , b< B (2 ^ 24) _) ,
  (b≤ (2 ^ 24) M _ , b< M (2 ^ 25) _ , (13981013 , refl)) ,
  ℕₚ.<⇒≱ (b< (2 ^ 48 ℕ.* gap (A ℕ.* 2 ^ 25) (M ℕ.* B)) (M ℕ.* B) _)
  where
  A = 13981011
  B = 16777213
  M = 27962027
  b≤ = ℕₚ.≤ᵇ⇒≤
  b< = ℕₚ.<ᵇ⇒<

-- no_tie_needs_normal, as a witness: with a subnormal midpoint (fewer than 25 bits) the tie
-- can happen. 1 * 2 = 1 * 2, with a1 = 1, b1 = 2 and m1 = 1 odd.
no-tie-needs-normal : let a1 = 1 ; b1 = 2 ; m1 = 1 in
  1 ≤ a1 × a1 < 2 ^ 24 × 1 ≤ b1 × b1 < 2 ^ 24 × m1 < 2 ^ 24 × Odd m1 × a1 ℕ.* 2 ≡ m1 ℕ.* b1
no-tie-needs-normal =
  s≤s z≤n , from-yes (1 ℕₚ.<? 2 ^ 24) , s≤s z≤n , from-yes (2 ℕₚ.<? 2 ^ 24) ,
  from-yes (1 ℕₚ.<? 2 ^ 24) , (0 , refl) , refl
