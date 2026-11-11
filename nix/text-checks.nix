# The text checks' shell (`nix develop .#text-checks`): GHC with the libraries that
# tools/text-checks/ compiles against, and Z3, which SBV runs as a process. Every version comes
# from flake.lock's nixpkgs: GHC 9.10, regex-pcre-builtin (PCRE 8.44 with Unicode properties),
# SBV, text and bytestring.
{ pkgs }:
let
  ghc = pkgs.haskellPackages.ghcWithPackages (p: [ p.regex-pcre-builtin p.sbv p.text p.bytestring p.containers ]);
in
pkgs.mkShell {
  packages = [ ghc pkgs.z3 pkgs.git ];
  LANG = "C.UTF-8";
}
