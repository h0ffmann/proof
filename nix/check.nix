# The check shell (`nix develop .#check --command just check`): every tool `just check` runs, from
# the other shells of nix/, so a tool is pinned in one file only. clingo of nix/invariants.nix, Lean
# of nix/lean.nix, GHC of nix/haskell.nix, and Pillow and ffmpeg of nix/roteiro-preview.nix. The
# Haskell tools under tools/ enter their own shells (nix/<tool>.nix) by themselves. `just liquid` enters
# nix/liquidhaskell.nix by itself. mkShell does not pass on the environment of inputsFrom, so the
# variables are set again.
{ pkgs }:
let
  shell = name: import (./. + "/${name}.nix") { inherit pkgs; };
  roteiro = shell "roteiro-preview";
in
pkgs.mkShell {
  inputsFrom = map shell [ "invariants" "lean" "haskell" "roteiro-preview" ];
  inherit (roteiro) ROTEIRO_FONT_DIR;
  LANG = "C.UTF-8";
}
