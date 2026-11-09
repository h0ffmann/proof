# The house-pricing shell (`nix develop .#house-pricing`, then `just house-pricing`): Rust with
# cargo and clippy for house-pricing/rust, Lean from nix/lean.nix for house-pricing/lean (build.rs
# finds its runtime with `lean --print-prefix`), and curl for data/fetch.sh, which checks the data
# against its SHA-256.
{ pkgs }:
let
  inherit (import ./lean.nix { inherit pkgs; }) lean;
in
pkgs.mkShell {
  packages = [
    pkgs.rustc
    pkgs.cargo
    pkgs.clippy
    pkgs.rustfmt
    lean
    pkgs.curl
    pkgs.gnutar
    pkgs.just
    pkgs.git
  ];
}
