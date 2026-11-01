//! Ridge regression, closed form, on a basis expansion of the features.
//! Prediction is a dot product, so it is exact in Lean `Rat` arithmetic.

#![allow(clippy::needless_range_loop)] // index loops read like the formulas

use crate::features::{FIRST_INDICATOR, N};

#[derive(Clone, Copy, Debug)]
pub enum Basis {
    /// the 15 features
    Linear,
    /// + squares and pairwise products of the 11 numeric features
    Quadratic,
}

pub fn expand(b: Basis, x: &[f64; N]) -> Vec<f64> {
    let mut v = x.to_vec();
    if let Basis::Quadratic = b {
        for i in 0..FIRST_INDICATOR {
            for j in i..FIRST_INDICATOR {
                v.push(x[i] * x[j]);
            }
        }
    }
    v
}

pub struct Ridge {
    pub basis: Basis,
    pub intercept: f64,
    /// weights on the *unstandardised* basis, so predict = intercept + w·φ(x)
    pub w: Vec<f64>,
}

impl Ridge {
    pub fn fit(basis: Basis, xs: &[[f64; N]], y: &[f64], lambda: f64) -> Ridge {
        let phi: Vec<Vec<f64>> = xs.iter().map(|x| expand(basis, x)).collect();
        let d = phi[0].len();
        let n = phi.len() as f64;
        // standardise so one lambda fits every column
        let mut mu = vec![0.0; d];
        let mut sd = vec![0.0; d];
        for r in &phi {
            for k in 0..d {
                mu[k] += r[k] / n;
            }
        }
        for r in &phi {
            for k in 0..d {
                sd[k] += (r[k] - mu[k]).powi(2) / n;
            }
        }
        for s in sd.iter_mut() {
            *s = if *s > 0.0 { s.sqrt() } else { 1.0 };
        }
        let ymu = y.iter().sum::<f64>() / n;
        let mut a = vec![vec![0.0; d]; d];
        let mut b = vec![0.0; d];
        for (r, &yy) in phi.iter().zip(y) {
            let z: Vec<f64> = (0..d).map(|k| (r[k] - mu[k]) / sd[k]).collect();
            for i in 0..d {
                b[i] += z[i] * (yy - ymu);
                for j in 0..=i {
                    a[i][j] += z[i] * z[j];
                }
            }
        }
        for i in 0..d {
            for j in 0..i {
                a[j][i] = a[i][j];
            }
            a[i][i] += lambda * n;
        }
        let beta = cholesky_solve(a, b);
        let w: Vec<f64> = (0..d).map(|k| beta[k] / sd[k]).collect();
        let intercept = ymu - (0..d).map(|k| w[k] * mu[k]).sum::<f64>();
        Ridge {
            basis,
            intercept,
            w,
        }
    }

    pub fn predict(&self, x: &[f64; N]) -> f64 {
        let phi = expand(self.basis, x);
        self.intercept + phi.iter().zip(&self.w).map(|(a, b)| a * b).sum::<f64>()
    }
}

fn cholesky_solve(mut a: Vec<Vec<f64>>, mut b: Vec<f64>) -> Vec<f64> {
    let d = b.len();
    for j in 0..d {
        let mut s = a[j][j];
        for k in 0..j {
            s -= a[j][k] * a[j][k];
        }
        let l = s.max(1e-12).sqrt();
        a[j][j] = l;
        for i in j + 1..d {
            let mut s = a[i][j];
            for k in 0..j {
                s -= a[i][k] * a[j][k];
            }
            a[i][j] = s / l;
        }
    }
    for i in 0..d {
        for k in 0..i {
            b[i] -= a[i][k] * b[k];
        }
        b[i] /= a[i][i];
    }
    for i in (0..d).rev() {
        for k in i + 1..d {
            b[i] -= a[k][i] * b[k];
        }
        b[i] /= a[i][i];
    }
    b
}
