# LiquidHaskell: the refinement types of the Haskell port (haskell/LIQUIDHASKELL.md).

# Check the refinement types of haskell/src with LiquidHaskell and Z3 (enters `nix develop
# .#liquidhaskell` when the tools are not on PATH). The self-test first shows that a wrong
# argmax fails. Also in `just check` and `just checks liquidhaskell`.
liquid:
    bash checks/liquidhaskell.sh --self-test

# The LiquidHaskell shell: GHC with the plugin, and Z3 (nix/liquidhaskell.nix)
liquid-shell:
    nix develop --extra-experimental-features 'nix-command flakes' .#liquidhaskell
