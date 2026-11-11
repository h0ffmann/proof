# The TV ratings pipeline's shell (`nix develop .#tv-ratings`): GHC with its bundled libraries
# (containers, directory, process, time) for tools/tv-ratings/, and curl with its CA bundle, which
# the pipeline runs to fetch the public pages. Every version comes from flake.lock's nixpkgs.
{ pkgs }:
let
  ghc = pkgs.haskellPackages.ghcWithPackages (p: [ p.containers p.directory p.process p.time ]);
in
pkgs.mkShell {
  packages = [ ghc pkgs.curl pkgs.cacert ];
  LANG = "C.UTF-8";
}
