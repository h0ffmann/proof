//! The Lean model through its C ABI (`lean/HousePricing/FFI.lean`).
//!
//! `Float` is a C `double` and `UInt8` a `uint8_t`, so the exported functions
//! take plain numbers. Lean must initialise its runtime and our module once.

use crate::data::Raw;
use std::ffi::c_void;
use std::sync::Once;

extern "C" {
    fn lean_initialize_runtime_module();
    fn lean_io_mark_end_initialization();
    fn initialize_HousePricing(builtin: u8, world: *mut c_void) -> *mut c_void;
    #[allow(clippy::too_many_arguments)]
    fn hp_predict(
        lon: f64,
        lat: f64,
        age: f64,
        rooms: f64,
        bedrooms: f64,
        population: f64,
        households: f64,
        income: f64,
        ocean: u8,
    ) -> f64;
    #[allow(clippy::too_many_arguments)]
    fn hp_predict_monotone(
        lon: f64,
        lat: f64,
        age: f64,
        rooms: f64,
        bedrooms: f64,
        population: f64,
        households: f64,
        income: f64,
        ocean: u8,
    ) -> f64;
    fn hp_chosen_lo(unit: *mut c_void) -> f64;
    fn hp_chosen_hi(unit: *mut c_void) -> f64;
}

/// `lean_box(0)`: the IO world token, and the value of `Unit`.
#[allow(clippy::manual_dangling_ptr)] // a tagged scalar, never dereferenced
const BOX0: *mut c_void = 1 as *mut c_void;

static INIT: Once = Once::new();

pub fn init() {
    INIT.call_once(|| unsafe {
        lean_initialize_runtime_module();
        let res = initialize_HousePricing(1, BOX0);
        // An `IO` result is a constructor object; tag 0 is `ok`. The tag is
        // the last byte of the 8-byte object header (see lean.h).
        let tag = *(res as *const u8).add(7);
        assert_eq!(tag, 0, "initialize_HousePricing failed");
        lean_io_mark_end_initialization();
    });
}

pub fn predict(r: &Raw) -> f64 {
    unsafe {
        hp_predict(
            r.lon,
            r.lat,
            r.age,
            r.rooms,
            r.bedrooms,
            r.population,
            r.households,
            r.income,
            r.ocean,
        )
    }
}

pub fn predict_monotone(r: &Raw) -> f64 {
    unsafe {
        hp_predict_monotone(
            r.lon,
            r.lat,
            r.age,
            r.rooms,
            r.bedrooms,
            r.population,
            r.households,
            r.income,
            r.ocean,
        )
    }
}

/// The proved bounds of the chosen model: no input gets a price outside them.
pub fn chosen_bounds() -> (f64, f64) {
    unsafe { (hp_chosen_lo(BOX0), hp_chosen_hi(BOX0)) }
}
