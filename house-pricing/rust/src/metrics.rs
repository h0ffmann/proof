//! Regression scores on US dollars.

#[derive(Clone, Copy, Debug)]
pub struct Scores {
    pub rmse: f64,
    pub mae: f64,
    pub r2: f64,
}

pub fn scores(y: &[f64], p: &[f64]) -> Scores {
    let n = y.len() as f64;
    let mean = y.iter().sum::<f64>() / n;
    let (mut se, mut ae, mut tot) = (0.0, 0.0, 0.0);
    for (a, b) in y.iter().zip(p) {
        se += (a - b) * (a - b);
        ae += (a - b).abs();
        tot += (a - mean) * (a - mean);
    }
    Scores {
        rmse: (se / n).sqrt(),
        mae: ae / n,
        r2: 1.0 - se / tot,
    }
}
