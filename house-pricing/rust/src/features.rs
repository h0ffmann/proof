//! Feature engineering. Mirrors Lean `HP.features` index for index: if you
//! change one, change the other (the parity test catches a mismatch).
//!
//! Units follow `data::Raw`: income in dollars, longitude and latitude in
//! hundredths of a degree. All features are whole numbers (exact in `f64`)
//! except the three ratios, which are one correctly rounded division each.

use crate::data::Raw;

pub const N: usize = 15;

#[allow(dead_code)] // documentation of the order; Lean `featuresTail` lists the same
pub const NAMES: [&str; N] = [
    "median_income (dollars)",
    "housing_median_age",
    "rooms_per_household",
    "bedrooms_per_room",
    "population_per_household",
    "longitude (1/100 degree)",
    "latitude (1/100 degree)",
    "lat_plus_lon",
    "lat_minus_lon",
    "households",
    "population",
    "ocean_inland",
    "ocean_near_bay",
    "ocean_near_ocean",
    "ocean_island",
];

/// Indices 11..15 are 0/1 indicators; `<1H OCEAN` is the base level.
pub const FIRST_INDICATOR: usize = 11;

pub fn features(r: &Raw) -> [f64; N] {
    let ind = |k: u8| if r.ocean == k { 1.0 } else { 0.0 };
    [
        r.income,
        r.age,
        r.rooms / r.households,
        r.bedrooms / r.rooms,
        r.population / r.households,
        r.lon,
        r.lat,
        r.lat + r.lon,
        r.lat - r.lon,
        r.households,
        r.population,
        ind(1),
        ind(2),
        ind(3),
        ind(4),
    ]
}
