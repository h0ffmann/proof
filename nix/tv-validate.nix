# The TV audience validation pipeline's shell (`nix develop .#tv-validate`): GHC with the Hackage
# libraries tools/tv-validate/ builds on, cabal-install, which builds the package offline from that
# set, and Python with what tv-audience/python/experiment.py needs to run as it is (export.py).
# Every version comes from flake.lock's nixpkgs: tools/tv-validate/README.md lists them.
#
# Not in this nixpkgs: hierarchicalforecast (Nixtla MinT). export.py reports that arm as not run,
# and the pipeline computes the same reconciliation in closed form.
{ pkgs }:
let
  ghc = pkgs.haskellPackages.ghcWithPackages (p: [
    p.ad
    p.aeson
    p.bytestring
    p.cassava
    p.containers
    p.hedgehog
    p.optparse-applicative
    p.tasty
    p.tasty-hedgehog
    p.tasty-hunit
    p.text
    p.vector
  ]);
  python = pkgs.python3.withPackages (p: [ p.numpy p.pandas p.scipy p.scikit-learn p.xgboost ]);
in
pkgs.mkShell {
  packages = [ ghc pkgs.cabal-install python ];
  LANG = "C.UTF-8";
}
