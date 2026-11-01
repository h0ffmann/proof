//! With `--features lean`, link the Lean-compiled model.
//! Needs `lake build HousePricing:static` in ../lean first, and `lean` on PATH
//! (or LEAN_PREFIX set) to find the Lean runtime.

use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var_os("CARGO_FEATURE_LEAN").is_none() {
        return;
    }
    let prefix = std::env::var("LEAN_PREFIX").unwrap_or_else(|_| {
        let out = Command::new("lean")
            .arg("--print-prefix")
            .output()
            .expect("`lean` not on PATH; install the toolchain in ../lean/lean-toolchain or set LEAN_PREFIX");
        String::from_utf8(out.stdout).unwrap().trim().to_string()
    });
    println!("cargo:rerun-if-env-changed=LEAN_PREFIX");
    let lean_lib = PathBuf::from(&prefix).join("lib/lean");
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let ours = manifest.join("../lean/.lake/build/lib");
    let archive = ours.join("libHousePricing.a");
    assert!(
        archive.exists(),
        "{} missing: run `lake build HousePricing:static` in ../lean",
        archive.display()
    );
    println!("cargo:rerun-if-changed={}", archive.display());
    println!("cargo:rustc-link-search=native={}", ours.display());
    println!("cargo:rustc-link-search=native={}", lean_lib.display());
    println!("cargo:rustc-link-lib=static=HousePricing");
    // The Lean runtime and core library (Init), shared, found again at run time.
    println!("cargo:rustc-link-lib=dylib=Init_shared");
    println!("cargo:rustc-link-lib=dylib=leanshared");
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lean_lib.display());
}
