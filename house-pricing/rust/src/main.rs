//! house-pricing: compare models on California Housing, pick the best one
//! that Lean can replicate exactly, export it, and check Lean against Rust.
//!
//! ```text
//! house-pricing train  [csv]   compare models, write model/gbt.txt, model/gbt-monotone.txt, model/report.md
//! house-pricing parity [csv]   (feature `lean`) Lean, through its C ABI, vs Rust on the test set
//! ```

mod data;
mod export;
mod features;
#[cfg(feature = "lean")]
mod lean_ffi;
mod linear;
mod metrics;
mod tree;

use data::Row;
use features::{features, N};
use linear::{Basis, Ridge};
use metrics::{scores, Scores};
use std::fmt::Write;
use std::time::Instant;
use tree::{fit_cart, fit_gbt, Ensemble, GbtParams, TreeParams};

const DEFAULT_CSV: &str = "../data/housing.csv";
const MODEL_PATH: &str = "../model/gbt.txt";
const MONO_PATH: &str = "../model/gbt-monotone.txt";
const REPORT_PATH: &str = "../model/report.md";
const TRAINED_LEAN: &str = "../lean/HousePricing/Trained.lean";
const SEED_TEST: u64 = 20_260_101;
const SEED_VAL: u64 = 20_260_102;

struct Split {
    train: Vec<Row>,
    fit: Vec<Row>,
    val: Vec<Row>,
    test: Vec<Row>,
}

fn xy(rows: &[Row]) -> (Vec<[f64; N]>, Vec<f64>) {
    (
        rows.iter().map(|r| features(&r.raw)).collect(),
        rows.iter().map(|r| r.value).collect(),
    )
}

fn load_split(csv: &str) -> (Split, data::LoadStats) {
    let (rows, st) = data::load(csv).unwrap_or_else(|e| {
        eprintln!("error: {e}");
        std::process::exit(1)
    });
    // 80 % train / 20 % test; inside train, 80 % fit / 20 % validation.
    let (train, test) = data::split(&rows, 0.8, SEED_TEST);
    let (fit, val) = data::split(&train, 0.8, SEED_VAL);
    (
        Split {
            train,
            fit,
            val,
            test,
        },
        st,
    )
}

/// Why a model can or cannot be replicated exactly by Lean's `Rat` evaluator.
#[derive(Clone, Copy)]
enum Lean {
    Exact(&'static str),
    No(&'static str),
}

struct Candidate {
    name: String,
    lean: Lean,
    config: String,
    val: Scores,
    test: Scores,
    size: String,
    secs: f64,
    model: Option<Ensemble>,
}

fn gbt(depth: usize, mono: Option<usize>, round_cents: bool) -> GbtParams {
    GbtParams {
        tree: TreeParams {
            max_depth: depth,
            min_leaf: 20,
            lambda: 1.0,
        },
        learning_rate: 0.1,
        subsample: 0.8,
        max_trees: 3000,
        patience: 100,
        mono_feature: mono,
        round_cents,
        seed: 7,
    }
}

fn train(csv: &str) {
    let (s, st) = load_split(csv);
    println!(
        "rows: {} read, {} without total_bedrooms, {} with the censored value {} -> {} kept",
        st.total,
        st.missing_bedrooms,
        st.capped_value,
        data::VALUE_CAP,
        st.kept
    );
    println!(
        "split: train {} (fit {} + validation {}), test {}",
        s.train.len(),
        s.fit.len(),
        s.val.len(),
        s.test.len()
    );
    let (fx, fy) = xy(&s.fit);
    let (vx, vy) = xy(&s.val);
    let (tx, ty) = xy(&s.train);
    let (ex, ey) = xy(&s.test);
    let mut cands: Vec<Candidate> = Vec::new();

    // 1. Mean: the floor every model must beat.
    {
        let t0 = Instant::now();
        let m = fy.iter().sum::<f64>() / fy.len() as f64;
        let mt = ty.iter().sum::<f64>() / ty.len() as f64;
        cands.push(Candidate {
            name: "mean".into(),
            lean: Lean::Exact("a constant"),
            config: "-".into(),
            val: scores(&vy, &vec![m; vy.len()]),
            test: scores(&ey, &vec![mt; ey.len()]),
            size: "1 number".into(),
            secs: t0.elapsed().as_secs_f64(),
            model: None,
        });
    }

    // 2. Ridge on the 15 features and on a quadratic expansion.
    for (name, basis) in [
        ("ridge", Basis::Linear),
        ("ridge, quadratic features", Basis::Quadratic),
    ] {
        let t0 = Instant::now();
        let mut best: Option<(f64, Scores)> = None;
        for lam in [1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1.0, 10.0] {
            let r = Ridge::fit(basis, &fx, &fy, lam);
            let p: Vec<f64> = vx.iter().map(|x| r.predict(x)).collect();
            let sc = scores(&vy, &p);
            if best.is_none_or(|b| sc.rmse < b.1.rmse) {
                best = Some((lam, sc));
            }
        }
        let (lam, val) = best.unwrap();
        let r = Ridge::fit(basis, &tx, &ty, lam);
        let p: Vec<f64> = ex.iter().map(|x| r.predict(x)).collect();
        cands.push(Candidate {
            name: name.into(),
            lean: Lean::Exact("a dot product"),
            config: format!("lambda={lam:e}"),
            val,
            test: scores(&ey, &p),
            size: format!("{} weights", r.w.len() + 1),
            secs: t0.elapsed().as_secs_f64(),
            model: None,
        });
    }

    // 3. One regression tree.
    {
        let t0 = Instant::now();
        let mut best: Option<(usize, Scores)> = None;
        for depth in [6, 8, 10, 12, 14] {
            let p = TreeParams {
                max_depth: depth,
                min_leaf: 20,
                lambda: 0.0,
            };
            let m = fit_cart(&fx, &fy, p);
            let sc = scores(&vy, &vx.iter().map(|x| m.predict(x)).collect::<Vec<_>>());
            if best.is_none_or(|b| sc.rmse < b.1.rmse) {
                best = Some((depth, sc));
            }
        }
        let (depth, val) = best.unwrap();
        let m = fit_cart(
            &tx,
            &ty,
            TreeParams {
                max_depth: depth,
                min_leaf: 20,
                lambda: 0.0,
            },
        );
        cands.push(Candidate {
            name: "regression tree".into(),
            lean: Lean::Exact("comparisons and a constant"),
            config: format!("depth={depth}"),
            val,
            test: scores(&ey, &ex.iter().map(|x| m.predict(x)).collect::<Vec<_>>()),
            size: format!("{} leaves", m.leaves()),
            secs: t0.elapsed().as_secs_f64(),
            model: None,
        });
    }

    // 4. Gradient boosting: plain, monotone in median_income, and on log(value).
    let variants: [(&str, Option<usize>, bool, Lean); 3] = [
        (
            "gradient boosting",
            None,
            false,
            Lean::Exact("comparisons and a sum"),
        ),
        (
            "gradient boosting, monotone in income",
            Some(0),
            false,
            Lean::Exact("comparisons and a sum"),
        ),
        (
            "gradient boosting on log(value)",
            None,
            true,
            Lean::No("needs exp, which core Lean does not define on Rat"),
        ),
    ];
    for (name, mono, log, lean) in variants {
        let t0 = Instant::now();
        let tf =
            |y: &[f64]| -> Vec<f64> { y.iter().map(|v| if log { v.ln() } else { *v }).collect() };
        let back = |v: f64| if log { v.exp() } else { v };
        let mut best: Option<(usize, usize, Scores)> = None;
        for depth in [4, 6, 8] {
            let p = gbt(depth, mono, !log);
            let m = fit_gbt(&fx, &tf(&fy), Some((&vx, &tf(&vy))), p);
            let sc = scores(
                &vy,
                &vx.iter().map(|x| back(m.predict(x))).collect::<Vec<_>>(),
            );
            println!(
                "  {name}: depth {depth}, {} trees, validation RMSE {:.0}",
                m.trees.len(),
                sc.rmse
            );
            if best.is_none_or(|b| sc.rmse < b.2.rmse) {
                best = Some((depth, m.trees.len(), sc));
            }
        }
        let (depth, ntrees, val) = best.unwrap();
        // Refit on all of train with the tree count found on validation.
        let mut p = gbt(depth, mono, !log);
        p.max_trees = ntrees;
        let m = fit_gbt(&tx, &tf(&ty), None, p);
        let test = scores(
            &ey,
            &ex.iter().map(|x| back(m.predict(x))).collect::<Vec<_>>(),
        );
        cands.push(Candidate {
            name: name.into(),
            lean,
            config: format!("depth={depth}, trees={ntrees}, lr=0.1, subsample=0.8"),
            val,
            test,
            size: format!("{} leaves", m.leaves()),
            secs: t0.elapsed().as_secs_f64(),
            model: if log { None } else { Some(m) },
        });
    }

    // Choose on validation RMSE among the models Lean replicates exactly.
    let chosen = cands
        .iter()
        .enumerate()
        .filter(|(_, c)| matches!(c.lean, Lean::Exact(_)) && c.model.is_some())
        .min_by(|a, b| a.1.val.rmse.partial_cmp(&b.1.val.rmse).unwrap())
        .map(|(i, _)| i)
        .unwrap();

    let mut rep = String::new();
    let _ = writeln!(rep, "# Model comparison\n");
    let _ = writeln!(
        rep,
        "Generated by `cargo run --release -- train`. Data: {} rows read, {} without `total_bedrooms` \
         and {} with the censored value 500001 dropped, {} kept. Split: train {} (fit {} + validation {}), \
         test {}. Hyperparameters are chosen on validation; the test set is used once. \
         RMSE and MAE are in US dollars.\n",
        st.total, st.missing_bedrooms, st.capped_value, st.kept, s.train.len(), s.fit.len(), s.val.len(), s.test.len()
    );
    let _ = writeln!(rep, "| Model | Lean replicates it exactly? | Config | Val RMSE | Test RMSE | Test MAE | Test R² | Size |");
    let _ = writeln!(rep, "|---|---|---|---:|---:|---:|---:|---|");
    for (i, c) in cands.iter().enumerate() {
        let lean = match c.lean {
            Lean::Exact(why) => format!("yes, {why}"),
            Lean::No(why) => format!("no, {why}"),
        };
        let mark = if i == chosen { " **(chosen)**" } else { "" };
        let _ = writeln!(
            rep,
            "| {}{} | {} | {} | {:.0} | {:.0} | {:.0} | {:.4} | {} |",
            c.name, mark, lean, c.config, c.val.rmse, c.test.rmse, c.test.mae, c.test.r2, c.size
        );
    }
    print!("\n{rep}");
    for c in &cands {
        println!("time {:>6.1} s  {}", c.secs, c.name);
    }

    let m = cands[chosen].model.as_ref().unwrap();
    let text = export::to_text(m);
    std::fs::create_dir_all("../model").unwrap();
    std::fs::write(MODEL_PATH, &text).unwrap();
    std::fs::write(REPORT_PATH, &rep).unwrap();
    // Also export the income-monotone model: Lean certifies its monotonicity.
    let mono = cands.iter().find(|c| c.name.contains("monotone")).unwrap();
    let mono_text = export::to_text(mono.model.as_ref().unwrap());
    std::fs::write(MONO_PATH, &mono_text).unwrap();
    std::fs::write(TRAINED_LEAN, export::trained_lean(&text, &mono_text)).unwrap();
    // The exported text is the single source of truth: re-read it and check.
    let back = export::from_text(&text).unwrap();
    let p: Vec<f64> = ex.iter().map(|x| back.predict(x)).collect();
    let sc = scores(&ey, &p);
    assert!(
        (sc.rmse - cands[chosen].test.rmse).abs() < 1e-6,
        "export changed the model"
    );
    println!(
        "\nwrote {MODEL_PATH} ({} trees, {} leaves, {} bytes), {MONO_PATH}, {REPORT_PATH} and {TRAINED_LEAN}",
        back.trees.len(),
        back.leaves(),
        text.len()
    );
}

#[cfg(feature = "lean")]
fn load_model(path: &str) -> Ensemble {
    let text =
        std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e} (run `train` first)"));
    export::from_text(&text).unwrap()
}

/// Compare Lean (exact `Rat`, through the C ABI) with Rust (`f64`) on every
/// test row. Exits 1 if any row differs by a cent or more.
#[cfg(feature = "lean")]
fn parity(csv: &str) {
    let (s, _) = load_split(csv);
    lean_ffi::init();
    let mut failed = false;
    type LeanFn = fn(&data::Raw) -> f64;
    let models: [(&str, &str, LeanFn); 2] = [
        ("chosen", MODEL_PATH, lean_ffi::predict),
        ("monotone", MONO_PATH, lean_ffi::predict_monotone),
    ];
    for (name, path, lean_fn) in models {
        let m = load_model(path);
        let (mut worst, mut flips) = (0.0f64, 0usize);
        let (mut yl, mut yr, mut ys) = (Vec::new(), Vec::new(), Vec::new());
        let t0 = Instant::now();
        for r in &s.test {
            let lean = lean_fn(&r.raw);
            let rust = m.predict(&features(&r.raw));
            let d = (rust - lean).abs();
            worst = worst.max(d);
            // Every leaf is a whole number of cents, so taking another path
            // through any tree moves the sum by at least a cent; rounding
            // error is about 1e-10 dollars.
            if d >= 0.005 {
                if flips == 0 && std::env::var_os("HP_DEBUG").is_some() {
                    eprintln!("first mismatch: {:?} rust {rust} lean {lean}", r.raw);
                }
                flips += 1;
            }
            yl.push(lean);
            yr.push(rust);
            ys.push(r.value);
        }
        let secs = t0.elapsed().as_secs_f64();
        let (sl, sr) = (scores(&ys, &yl), scores(&ys, &yr));
        println!(
            "{name:8} {} test rows: max |Lean - Rust| = {worst:.2e} dollars, rows off by a cent or more: {flips}",
            s.test.len()
        );
        println!(
            "{:8} test RMSE Lean {:.2} / Rust {:.2}, R² {:.4}; Lean through the C ABI took {secs:.2} s",
            "", sl.rmse, sr.rmse, sl.r2
        );
        failed |= flips > 0;
    }
    let (lo, hi) = lean_ffi::chosen_bounds();
    println!(
        "chosen model, proved for every input (Lean `chosen_bounds`): {lo:.2} <= price <= {hi:.2}"
    );
    if failed {
        std::process::exit(1);
    }
    println!("parity OK");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let csv = args.get(2).map(String::as_str).unwrap_or(DEFAULT_CSV);
    match args.get(1).map(String::as_str) {
        Some("train") => train(csv),
        #[cfg(feature = "lean")]
        Some("parity") => parity(csv),
        #[cfg(not(feature = "lean"))]
        Some("parity") => {
            eprintln!(
                "parity needs the Lean library: cargo run --release --features lean -- parity"
            );
            std::process::exit(2)
        }
        _ => {
            eprintln!("usage: house-pricing train|parity [csv]");
            std::process::exit(2)
        }
    }
}
