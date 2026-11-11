# The Manim shell (`nix develop .#manim`): the animations of the video script, in the style of
# 3Blue1Brown (contextual-bandits/script/animation/, one scene per take). Manim Community
# from nixpkgs, with what it calls at render time: ffmpeg for the video, and a LaTeX with the
# packages MathTex and Tex load (standalone, preview, amsmath, babel-portuges for the captions).
# Render the takes with `just takes` (render.sh there calls `python3 -m manim`, because the `manim`
# program's wrapper puts a TeX Live without babel-portuges first on PATH).
{ pkgs }:
let
  tex = pkgs.texliveSmall.withPackages (p: [
    p.standalone p.preview p.doublestroke p.relsize p.fundus-calligra p.wasysym p.physics
    p.dvisvgm p.rsfs p.wasy p.cm-super p.babel-english p.babel-portuges p.everysel
    p.setspace p.microtype p.mathastext p.xcolor
  ]);
in
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (p: [ p.manim ]))
    pkgs.ffmpeg-headless
    tex
    pkgs.just
  ];
  LANG = "C.UTF-8";
}
