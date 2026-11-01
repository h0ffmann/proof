import HousePricing.Theorems
import HousePricing.Trained

/-!
# C ABI for the Rust host

`lake build HousePricing:static` compiles this package to C and then to a
static library. Rust calls `hp_predict` (see `rust/src/lean_ffi.rs`). `Float`
and `UInt8` cross the ABI as C `double` and `uint8_t`.

Each input `Float` becomes the `Rat` with exactly the same value
(`ofFloat`), so Lean sees the numbers Rust sees. Lean then computes the
features and the prediction exactly; only the final result is rounded back to
`Float`.
-/

namespace HP

/-- The exact rational value of a finite `Float`: `x = m · 2^e`, `m · 2^53` is an integer. -/
def ofFloat (x : Float) : Rat :=
  let (m, e) := x.frExp
  let k : Int := (m.scaleB 53).toInt64.toInt
  let s : Int := e - 53
  if 0 ≤ s then (k * 2 ^ s.toNat : Int) else mkRat k (2 ^ (-s).toNat)

def toFloat (q : Rat) : Float := Float.ofInt q.num / Float.ofNat q.den

def rawOfFloats (lon lat age rooms bedrooms population households income : Float)
    (ocean : UInt8) : Raw :=
  { lon := ofFloat lon, lat := ofFloat lat, age := ofFloat age, rooms := ofFloat rooms,
    bedrooms := ofFloat bedrooms, population := ofFloat population,
    households := ofFloat households, income := ofFloat income, ocean := .ofCode ocean }

/-- The chosen model's price for one raw row. -/
@[export hp_predict]
def predictC (lon lat age rooms bedrooms population households income : Float)
    (ocean : UInt8) : Float :=
  toFloat (predictRaw chosen (rawOfFloats lon lat age rooms bedrooms population households income ocean))

/-- The income-monotone model's price for one raw row. -/
@[export hp_predict_monotone]
def predictMonotoneC (lon lat age rooms bedrooms population households income : Float)
    (ocean : UInt8) : Float :=
  toFloat (predictRaw monotone (rawOfFloats lon lat age rooms bedrooms population households income ocean))

/-- The proved bounds `[lo, hi]` of the chosen model, for the Rust side to print. -/
@[export hp_chosen_lo] def chosenLoC (_ : Unit) : Float := toFloat chosen.lo
@[export hp_chosen_hi] def chosenHiC (_ : Unit) : Float := toFloat chosen.hi

end HP
