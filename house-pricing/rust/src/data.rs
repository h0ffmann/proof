//! Load, filter and split the California Housing CSV.

use std::fs;

/// `ocean_proximity`, in the order the Lean `Ocean` type lists it.
pub const OCEAN: [&str; 5] = ["<1H OCEAN", "INLAND", "NEAR BAY", "NEAR OCEAN", "ISLAND"];

/// One census block group, before feature engineering. Mirrors Lean `HP.Raw`.
///
/// Every field holds a whole number, so it is exact in `f64` and in Lean:
/// `lon` and `lat` in hundredths of a degree (the CSV has two decimals),
/// `income` in dollars (the CSV gives tens of thousands with four decimals),
/// the rest are counts and years. Then the only rounded feature values in Rust
/// are the three ratios, and `tree::short_between` keeps those on the same side
/// of every threshold as Lean's exact ones.
#[derive(Clone, Copy, Debug)]
pub struct Raw {
    pub lon: f64,
    pub lat: f64,
    pub age: f64,
    pub rooms: f64,
    pub bedrooms: f64,
    pub population: f64,
    pub households: f64,
    pub income: f64,
    pub ocean: u8,
}

#[derive(Clone, Copy, Debug)]
pub struct Row {
    pub raw: Raw,
    /// median_house_value in US dollars
    pub value: f64,
}

#[derive(Debug, Default)]
pub struct LoadStats {
    pub total: usize,
    pub missing_bedrooms: usize,
    pub capped_value: usize,
    pub kept: usize,
}

/// The census caps `median_house_value` at 500 001. Those labels are censored,
/// so we drop them instead of teaching every model a fake ceiling.
pub const VALUE_CAP: f64 = 500_001.0;

pub fn load(path: &str) -> Result<(Vec<Row>, LoadStats), String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{path}: {e} (run data/fetch.sh)"))?;
    let mut lines = text.lines();
    let header = lines.next().ok_or("empty file")?;
    let expect = "longitude,latitude,housing_median_age,total_rooms,total_bedrooms,population,households,median_income,median_house_value,ocean_proximity";
    if header.trim() != expect {
        return Err(format!("unexpected header: {header}"));
    }
    let mut st = LoadStats::default();
    let mut rows = Vec::new();
    for (i, line) in lines.enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        st.total += 1;
        let c: Vec<&str> = line.split(',').collect();
        if c.len() != 10 {
            return Err(format!("line {}: {} fields", i + 2, c.len()));
        }
        if c[4].is_empty() {
            st.missing_bedrooms += 1;
            continue;
        }
        let num = |k: usize| -> Result<f64, String> {
            c[k].parse::<f64>()
                .map_err(|e| format!("line {}: field {k}: {e}", i + 2))
        };
        // `x` times `scale`, which must be a whole number (the CSV's precision).
        let whole = |k: usize, scale: f64| -> Result<f64, String> {
            let v = num(k)? * scale;
            let r = v.round();
            if (v - r).abs() > 1e-6 {
                return Err(format!(
                    "line {}: field {k} = {} has more decimals than expected",
                    i + 2,
                    c[k]
                ));
            }
            Ok(r)
        };
        let ocean = OCEAN
            .iter()
            .position(|o| *o == c[9])
            .ok_or_else(|| format!("line {}: ocean_proximity {}", i + 2, c[9]))?
            as u8;
        let raw = Raw {
            lon: whole(0, 100.0)?,
            lat: whole(1, 100.0)?,
            age: whole(2, 1.0)?,
            rooms: whole(3, 1.0)?,
            bedrooms: whole(4, 1.0)?,
            population: whole(5, 1.0)?,
            households: whole(6, 1.0)?,
            income: whole(7, 10_000.0)?,
            ocean,
        };
        let value = num(8)?;
        if value >= VALUE_CAP {
            st.capped_value += 1;
            continue;
        }
        // Ratios divide by these; the data has none at zero, but say so. The
        // numerators stay below 2^16, which `tree::short_between` relies on.
        if raw.households <= 0.0 || raw.rooms <= 0.0 {
            return Err(format!("line {}: zero households or rooms", i + 2));
        }
        if raw.rooms.max(raw.bedrooms).max(raw.population) >= 65_536.0 {
            return Err(format!("line {}: a count of 2^16 or more", i + 2));
        }
        rows.push(Row { raw, value });
    }
    st.kept = rows.len();
    Ok((rows, st))
}

/// SplitMix64: small, seedable, the same generator the Haskell bandit port uses.
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng(seed)
    }
    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    /// Uniform in [0, 1).
    pub fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }
    pub fn below(&mut self, n: usize) -> usize {
        (self.next_u64() % n as u64) as usize
    }
}

/// Fisher-Yates shuffle with a fixed seed, then cut: (first, rest).
pub fn split<T: Clone>(xs: &[T], frac_first: f64, seed: u64) -> (Vec<T>, Vec<T>) {
    let mut idx: Vec<usize> = (0..xs.len()).collect();
    let mut rng = Rng::new(seed);
    for i in (1..idx.len()).rev() {
        let j = rng.below(i + 1);
        idx.swap(i, j);
    }
    let cut = (xs.len() as f64 * frac_first).round() as usize;
    let a = idx[..cut].iter().map(|&i| xs[i].clone()).collect();
    let b = idx[cut..].iter().map(|&i| xs[i].clone()).collect();
    (a, b)
}
