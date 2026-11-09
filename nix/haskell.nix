# The Haskell shell (`nix develop .#haskell`): GHC and cabal-install for haskell/ (`cabal run
# examples`, and the plain `ghc -O2 -Wall` build of `just check`). The package uses base and
# containers only, both shipped with GHC. LiquidHaskell has its own shell, nix/liquidhaskell.nix,
# on the same GHC.
{ pkgs }:
pkgs.mkShell {
  packages = [ pkgs.haskellPackages.ghc pkgs.cabal-install pkgs.just ];
  LANG = "C.UTF-8";
}
