# The port audit's shell (`nix develop .#port-audit`): GHC with SBV for tools/port-audit/, Z3, which
# SBV runs as a process, and git, which fetches the two pins of the coverage count. Every version
# comes from flake.lock's nixpkgs.
{ pkgs }:
let
  ghc = pkgs.haskellPackages.ghcWithPackages (p: [ p.sbv p.containers p.parsec p.directory p.process ]);
in
pkgs.mkShell {
  packages = [ ghc pkgs.z3 pkgs.git ];
  LANG = "C.UTF-8";
}
