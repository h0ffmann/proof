# The Invariants.lp shell (`nix develop .#invariants`): clingo, the answer set solver that decides
# Invariants.lp, with Python and git for scripts/invariants.py. From the nixpkgs that flake.lock pins.
{ pkgs }:
pkgs.mkShell {
  packages = [ pkgs.clingo pkgs.python3 pkgs.git ];
}
