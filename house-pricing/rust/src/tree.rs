//! Regression trees and gradient boosting (squared loss), histogram based.
//! A tree is only comparisons `x[f] <= t` and constant leaves, and an ensemble
//! is a sum, so Lean evaluates it exactly in `Rat`.

use crate::data::Rng;
use crate::features::N;

#[derive(Clone, Debug)]
pub enum Node {
    Leaf(f64),
    /// go left when `x[feat] <= thr`
    Split {
        feat: usize,
        thr: f64,
        left: Box<Node>,
        right: Box<Node>,
    },
}

impl Node {
    pub fn eval(&self, x: &[f64; N]) -> f64 {
        let mut n = self;
        loop {
            match n {
                Node::Leaf(v) => return *v,
                Node::Split {
                    feat,
                    thr,
                    left,
                    right,
                } => {
                    n = if x[*feat] <= *thr { left } else { right };
                }
            }
        }
    }
    pub fn leaves(&self) -> usize {
        match self {
            Node::Leaf(_) => 1,
            Node::Split { left, right, .. } => left.leaves() + right.leaves(),
        }
    }
    fn map_leaves(&mut self, f: &dyn Fn(f64) -> f64) {
        match self {
            Node::Leaf(v) => *v = f(*v),
            Node::Split { left, right, .. } => {
                left.map_leaves(f);
                right.map_leaves(f);
            }
        }
    }
}

/// A threshold between two neighbouring training values a < b: the dyadic
/// number m / 2^k with the smallest k (at most 30) in the middle half of (a, b).
///
/// Why this is safe for Lean, which computes features exactly:
/// * a dyadic threshold is an `f64` exactly, and its decimal expansion is
///   finite (`exact_decimal`), so Lean compares against the very same number;
/// * whole-number features are exact on both sides, so they agree;
/// * a ratio p / q (p, q whole, p < 2^16) is rounded once by Rust. Rounding
///   is monotone and keeps t fixed, so Rust's and Lean's values can only fall
///   on different sides of t when p / q ≠ t and |p / q - t| is below half an
///   ulp of p / q, about (p / q) 2^-53. But p / q - t is a nonzero multiple of
///   1 / (q 2^k), so that needs p 2^k ≥ 2^53, impossible for p < 2^16, k ≤ 30.
///
/// A short decimal such as `152.35` would not do: it is not an `f64`.
pub fn short_between(a: f64, b: f64) -> f64 {
    let (lo, hi) = (a + 0.25 * (b - a), b - 0.25 * (b - a));
    for k in 0..=MAX_DYADIC_BITS {
        let scale = (k as f64).exp2();
        let m = (lo * scale).ceil();
        if m.abs() < (1u64 << 53) as f64 && m / scale <= hi {
            return m / scale;
        }
    }
    0.5 * (a + b)
}

/// Thresholds use at most this many binary digits after the point, so that
/// `exact_decimal` fits in a u128.
pub const MAX_DYADIC_BITS: u32 = 30;

/// The exact decimal expansion of a dyadic `f64` m / 2^k with k <= 30, for
/// example `0.375` or `-118.30078125`; `None` if `x` is not of that form.
pub fn exact_decimal(x: f64) -> Option<String> {
    for k in 0..=MAX_DYADIC_BITS {
        let m = x * (k as f64).exp2();
        if m.fract() == 0.0 && m.abs() < (1u64 << 53) as f64 {
            let digits = (m.abs() as u128) * 5u128.pow(k);
            let s = format!("{digits:0>width$}", width = k as usize + 1);
            let (int, frac) = s.split_at(s.len() - k as usize);
            let sign = if m < 0.0 { "-" } else { "" };
            return Some(if k == 0 {
                format!("{sign}{int}")
            } else {
                format!("{sign}{int}.{frac}")
            });
        }
    }
    None
}

/// Up to 255 cut points per feature, from training quantiles.
pub fn bin_edges(xs: &[[f64; N]]) -> Vec<Vec<f64>> {
    (0..N)
        .map(|f| {
            let mut v: Vec<f64> = xs.iter().map(|x| x[f]).collect();
            v.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let mut uniq = v.clone();
            uniq.dedup();
            let mut edges = Vec::new();
            if uniq.len() <= 256 {
                for w in uniq.windows(2) {
                    edges.push(short_between(w[0], w[1]));
                }
            } else {
                for k in 1..256 {
                    let a = v[k * v.len() / 256 - 1];
                    let j = uniq.partition_point(|u| *u <= a);
                    if j < uniq.len() {
                        let e = short_between(a, uniq[j]);
                        if edges.last().is_none_or(|l| *l < e) {
                            edges.push(e);
                        }
                    }
                }
            }
            edges
        })
        .collect()
}

/// `bin(x) <= k  <=>  x <= edges[k]`
pub fn bin_of(edges: &[f64], x: f64) -> u8 {
    edges.partition_point(|e| *e < x) as u8
}

#[derive(Clone, Copy, Debug)]
pub struct TreeParams {
    pub max_depth: usize,
    pub min_leaf: usize,
    pub lambda: f64,
}

struct Grower<'a> {
    bins: &'a [Vec<u8>], // [feature][row]
    edges: &'a [Vec<f64>],
    p: TreeParams,
    /// +1: prediction must not decrease in this feature
    mono: [i8; N],
}

impl Grower<'_> {
    fn grow(&self, rows: &mut [u32], g: &[f64], depth: usize, lo: f64, hi: f64) -> Node {
        let lam = self.p.lambda;
        let n = rows.len();
        let gsum: f64 = rows.iter().map(|&r| g[r as usize]).sum();
        let leaf = (gsum / (n as f64 + lam)).clamp(lo, hi);
        if depth >= self.p.max_depth || n < 2 * self.p.min_leaf {
            return Node::Leaf(leaf);
        }
        let parent = gsum * gsum / (n as f64 + lam);
        let mut best: Option<(f64, usize, usize, f64, f64)> = None; // gain, feat, k, wl, wr
        let mut hg = [0.0f64; 256];
        let mut hc = [0usize; 256];
        for f in 0..N {
            let nb = self.edges[f].len() + 1;
            if nb < 2 {
                continue;
            }
            hg[..nb].fill(0.0);
            hc[..nb].fill(0);
            let col = &self.bins[f];
            for &r in rows.iter() {
                let b = col[r as usize] as usize;
                hg[b] += g[r as usize];
                hc[b] += 1;
            }
            let (mut gl, mut cl) = (0.0, 0usize);
            for k in 0..nb - 1 {
                gl += hg[k];
                cl += hc[k];
                let cr = n - cl;
                if cl < self.p.min_leaf {
                    continue;
                }
                if cr < self.p.min_leaf {
                    break;
                }
                let gr = gsum - gl;
                let wl = (gl / (cl as f64 + lam)).clamp(lo, hi);
                let wr = (gr / (cr as f64 + lam)).clamp(lo, hi);
                if self.mono[f] > 0 && wl > wr {
                    continue;
                }
                let gain = gl * gl / (cl as f64 + lam) + gr * gr / (cr as f64 + lam) - parent;
                if gain > 1e-9 && best.is_none_or(|b| gain > b.0) {
                    best = Some((gain, f, k, wl, wr));
                }
            }
        }
        let Some((_, f, k, wl, wr)) = best else {
            return Node::Leaf(leaf);
        };
        let col = &self.bins[f];
        let mut i = 0;
        for j in 0..n {
            if (col[rows[j] as usize] as usize) <= k {
                rows.swap(i, j);
                i += 1;
            }
        }
        let (lb, rb) = if self.mono[f] > 0 {
            let mid = 0.5 * (wl + wr);
            ((lo, hi.min(mid)), (lo.max(mid), hi))
        } else {
            ((lo, hi), (lo, hi))
        };
        let (l, r) = rows.split_at_mut(i);
        Node::Split {
            feat: f,
            thr: self.edges[f][k],
            left: Box::new(self.grow(l, g, depth + 1, lb.0, lb.1)),
            right: Box::new(self.grow(r, g, depth + 1, rb.0, rb.1)),
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct GbtParams {
    pub tree: TreeParams,
    pub learning_rate: f64,
    pub subsample: f64,
    pub max_trees: usize,
    /// stop when the validation RMSE has not improved for this many trees
    pub patience: usize,
    /// feature that must act monotonically (non-decreasing), if any
    pub mono_feature: Option<usize>,
    /// round leaves to whole cents (only for a model on dollars)
    pub round_cents: bool,
    pub seed: u64,
}

#[derive(Clone, Debug)]
pub struct Ensemble {
    pub base: f64,
    pub trees: Vec<Node>,
}

impl Ensemble {
    pub fn predict(&self, x: &[f64; N]) -> f64 {
        self.trees.iter().fold(self.base, |s, t| s + t.eval(x))
    }
    pub fn leaves(&self) -> usize {
        self.trees.iter().map(|t| t.leaves()).sum()
    }
}

fn binned(xs: &[[f64; N]], edges: &[Vec<f64>]) -> Vec<Vec<u8>> {
    (0..N)
        .map(|f| xs.iter().map(|x| bin_of(&edges[f], x[f])).collect())
        .collect()
}

/// A single CART tree (one boosting round with learning rate 1).
pub fn fit_cart(xs: &[[f64; N]], y: &[f64], p: TreeParams) -> Ensemble {
    let edges = bin_edges(xs);
    let bins = binned(xs, &edges);
    let base = y.iter().sum::<f64>() / y.len() as f64;
    let g: Vec<f64> = y.iter().map(|v| v - base).collect();
    let gr = Grower {
        bins: &bins,
        edges: &edges,
        p,
        mono: [0; N],
    };
    let mut rows: Vec<u32> = (0..xs.len() as u32).collect();
    let t = gr.grow(&mut rows, &g, 0, f64::NEG_INFINITY, f64::INFINITY);
    Ensemble {
        base,
        trees: vec![t],
    }
}

/// Gradient boosting. With `val`, stops early and keeps the best prefix;
/// returns the model and its number of trees.
pub fn fit_gbt(
    xs: &[[f64; N]],
    y: &[f64],
    val: Option<(&[[f64; N]], &[f64])>,
    p: GbtParams,
) -> Ensemble {
    let edges = bin_edges(xs);
    let bins = binned(xs, &edges);
    let mut mono = [0i8; N];
    if let Some(f) = p.mono_feature {
        mono[f] = 1;
    }
    let gr = Grower {
        bins: &bins,
        edges: &edges,
        p: p.tree,
        mono,
    };
    let base = y.iter().sum::<f64>() / y.len() as f64;
    let mut pred = vec![base; xs.len()];
    let mut vpred: Vec<f64> = val.map(|(vx, _)| vec![base; vx.len()]).unwrap_or_default();
    let mut rng = Rng::new(p.seed);
    let mut trees = Vec::new();
    let (mut best_rmse, mut best_len) = (f64::INFINITY, 0);
    let lr = p.learning_rate;
    for _ in 0..p.max_trees {
        let g: Vec<f64> = y.iter().zip(&pred).map(|(a, b)| a - b).collect();
        let mut rows: Vec<u32> = (0..xs.len() as u32)
            .filter(|_| rng.next_f64() < p.subsample)
            .collect();
        let mut t = gr.grow(&mut rows, &g, 0, f64::NEG_INFINITY, f64::INFINITY);
        // Scale and round to whole cents: short literals for Lean, and rounding
        // is monotone, so a monotone tree stays monotone.
        if p.round_cents {
            t.map_leaves(&|v| (v * lr * 100.0).round() / 100.0);
        } else {
            t.map_leaves(&|v| v * lr);
        }
        for (pv, x) in pred.iter_mut().zip(xs) {
            *pv += t.eval(x);
        }
        trees.push(t);
        if let Some((vx, vy)) = val {
            let mut se = 0.0;
            for ((pv, x), yy) in vpred.iter_mut().zip(vx).zip(vy) {
                *pv += trees.last().unwrap().eval(x);
                se += (*pv - yy) * (*pv - yy);
            }
            let rmse = (se / vx.len() as f64).sqrt();
            if rmse < best_rmse {
                best_rmse = rmse;
                best_len = trees.len();
            } else if trees.len() - best_len >= p.patience {
                break;
            }
        }
    }
    if val.is_some() {
        trees.truncate(best_len);
    }
    Ensemble { base, trees }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thresholds_are_dyadic_and_inside() {
        for (a, b) in [
            (152.33, 152.37),
            (0.1, 0.2),
            (-118.31, -118.3),
            (681.0, 682.0),
            (2.4048, 2.4049),
        ] {
            let t = short_between(a, b);
            assert!(a < t && t < b, "{a} {b} {t}");
            let s = exact_decimal(t).unwrap();
            assert_eq!(s.parse::<f64>().unwrap(), t);
        }
        assert_eq!(exact_decimal(-118.30078125).unwrap(), "-118.30078125");
        assert_eq!(exact_decimal(681.5).unwrap(), "681.5");
        assert_eq!(exact_decimal(3.0).unwrap(), "3");
        assert_eq!(exact_decimal(0.375).unwrap(), "0.375");
        assert!(exact_decimal(0.1).is_none());
    }
}
