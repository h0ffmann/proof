# The roteiro-preview shell (`nix develop .#roteiro-preview`, then `just sp-preview`): Python with
# Pillow, ffmpeg and ffprobe for the video, espeak-ng for the narration, and the DejaVu fonts, which
# preview.py finds through ROTEIRO_FONT_DIR. checks/roteiro-preview.sh renders in this shell.
{ pkgs }:
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (p: [ p.pillow ]))
    pkgs.ffmpeg-headless
    pkgs.espeak-ng
    pkgs.just
  ];
  ROTEIRO_FONT_DIR = "${pkgs.dejavu_fonts}/share/fonts";
}
