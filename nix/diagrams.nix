# The diagrams shell (`nix develop .#diagrams`, then `just diagrams` and `just images`): Node for
# vendor/archify (it needs no npm package at run time), Python for build_candidates.py, and
# Chromium for archify's browser gate, named by ARCHIFY_CHROME. nixpkgs builds Chromium for Linux
# only; on macOS archify finds an installed Chrome by itself.
{ pkgs }:
pkgs.mkShell ({
  packages = [ pkgs.nodejs_22 pkgs.python3 pkgs.just ]
    ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.chromium;
} // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  ARCHIFY_CHROME = "${pkgs.chromium}/bin/chromium";
})
