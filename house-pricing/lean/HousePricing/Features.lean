/-!
# Inputs and feature engineering

`Raw` is one census block group as the CSV gives it. `features` turns it into
the 15 numbers the model reads. The Rust port (`rust/src/features.rs`) lists
the same features in the same order.

Units: `lon` and `lat` in hundredths of a degree, `income` in dollars, the
rest are counts and years. With these units every raw value in the data is a
whole number, so Rust holds it exactly too, and the only features Rust rounds
are the three ratios (see `short_between` in `rust/src/tree.rs`).

Ratios divide by `households` and `rooms`. Lean's `x / 0 = 0`, Rust's is `inf`,
so the two agree only when both are positive. The Rust loader rejects rows
where they are not.
-/

namespace HP

/-- `ocean_proximity`. The order is the code the Rust side passes (0..4). -/
inductive Ocean
  | lessThan1h | inland | nearBay | nearOcean | island
  deriving DecidableEq, Repr, Inhabited

def Ocean.ofCode : UInt8 → Ocean
  | 1 => .inland | 2 => .nearBay | 3 => .nearOcean | 4 => .island | _ => .lessThan1h

structure Raw where
  /-- longitude, 1/100 degree -/
  lon : Rat
  /-- latitude, 1/100 degree -/
  lat : Rat
  /-- housing median age, years -/
  age : Rat
  rooms : Rat
  bedrooms : Rat
  population : Rat
  households : Rat
  /-- median income, dollars -/
  income : Rat
  ocean : Ocean
  deriving Repr, Inhabited

/-- Number of features. -/
abbrev F := 15

/-- A feature vector. -/
abbrev Vec := Fin F → Rat

def indicator (o : Ocean) (r : Raw) : Rat := if r.ocean = o then 1 else 0

/-- Every feature except `median_income` (index 0), in order. -/
def featuresTail (r : Raw) : List Rat :=
  [ r.age,
    r.rooms / r.households,
    r.bedrooms / r.rooms,
    r.population / r.households,
    r.lon,
    r.lat,
    r.lat + r.lon,
    r.lat - r.lon,
    r.households,
    r.population,
    indicator .inland r,
    indicator .nearBay r,
    indicator .nearOcean r,
    indicator .island r ]

def features (r : Raw) : Vec := fun i => (r.income :: featuresTail r).getD i.val 0

end HP
