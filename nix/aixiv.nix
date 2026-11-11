# The aiXiv shell (`nix develop .#aixiv`): curl with its CA bundle, which scripts/aixiv.sh runs to
# call aiXiv's API, and jq, which reads papers/*/aixiv.json and the answers. From flake.lock's nixpkgs.
{ pkgs }:
pkgs.mkShell {
  packages = [ pkgs.curl pkgs.cacert pkgs.jq ];
  LANG = "C.UTF-8";
}
