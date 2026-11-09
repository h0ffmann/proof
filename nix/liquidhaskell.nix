# The LiquidHaskell shell (`nix develop .#liquidhaskell`): GHC with the LiquidHaskell plugin, and
# Z3, the SMT solver the plugin calls. All three come from the nixpkgs that flake.lock pins, so the
# plugin always matches its GHC (at the pin: GHC 9.10.3, liquidhaskell 0.9.10.1.2, Z3 5.1.0).
# checks/liquidhaskell.sh enters it by itself; haskell/LIQUIDHASKELL.md says what is checked.
{ pkgs }:
pkgs.mkShell {
  packages = [
    (pkgs.haskellPackages.ghcWithPackages (p: [ p.liquidhaskell ]))
    pkgs.z3
    pkgs.just
  ];
  # LiquidHaskell reads the sources as text; Models.hs has non-ASCII comments.
  LANG = "C.UTF-8";
}
