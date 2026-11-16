# The tv-z3 shell (`nix develop .#tv-z3`): GHC with SBV for tools/tv-z3/ and Z3, which SBV runs as
# a process. Every version comes from flake.lock's nixpkgs.
{ pkgs }:
let
  ghc = pkgs.haskellPackages.ghcWithPackages (p: [ p.sbv p.containers ]);
in
pkgs.mkShell {
  packages = [ ghc pkgs.z3 ];
  LANG = "C.UTF-8";
}
