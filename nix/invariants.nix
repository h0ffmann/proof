# The Invariants.lp shell (`nix develop .#invariants`): clingo, the answer set solver that decides
# Invariants.lp, and GHC with regex-pcre-builtin and text for tools/invariants/, which reads the
# facts, and git. From the nixpkgs that flake.lock pins.
{ pkgs }:
let
  ghc = pkgs.haskellPackages.ghcWithPackages (p: [ p.regex-pcre-builtin p.text p.bytestring p.containers ]);
in
pkgs.mkShell {
  packages = [ pkgs.clingo ghc pkgs.git ];
  LANG = "C.UTF-8";
}
