# The check shell (`nix develop .#check --command just check`): every tool `just check` runs, from
# the other shells of nix/, so a tool is pinned in one file only. The JDK, sbt and Z3_HOME of
# nix/scala.nix (the Z3 checks, Leo-III), clingo of nix/invariants.nix, Lean of nix/lean.nix, GHC
# of nix/haskell.nix, and Pillow and ffmpeg of nix/roteiro-preview.nix. `just liquid` enters
# nix/liquidhaskell.nix by itself. mkShell does not pass on the environment of inputsFrom, so the
# variables are set again.
{ pkgs }:
let
  shell = name: import (./. + "/${name}.nix") { inherit pkgs; };
  scala = shell "scala";
  roteiro = shell "roteiro-preview";
in
pkgs.mkShell {
  inputsFrom = map shell [ "scala" "invariants" "lean" "haskell" "roteiro-preview" ];
  inherit (scala) JAVA_HOME Z3_HOME;
  inherit (roteiro) ROTEIRO_FONT_DIR;
  LANG = "C.UTF-8";
}
