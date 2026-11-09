# The browsable index of proof (site/build.py): index.html, the preprints as PDF, the pages as HTML,
# the video script's preview and the archify diagrams, in one folder that a web server can serve at
# any path, because every link in it is relative. `just site` builds it with the nixpkgs of
# flake.lock. Another Nix configuration builds it from a copy of the repository at a pinned commit:
#
#   pkgs.callPackage "${src}/site" { rev = "<commit>"; }
#
# The output holds only files: allowedReferences = [ ] fails the build if it names a store path, so
# no tool of the build reaches the closure of the host that serves it.
{ lib
, stdenvNoCC
, python3
, pandoc
, haskellPackages
, texliveMedium
, ffmpeg
, dejavu_fonts
, makeFontsConf
, rev ? "main"        # the commit that the links to GitHub point at
, stamp ? null       # the revision printed on the pages and the PDFs; default: rev, short
}:
let
  # The TeX Live of the paper lab (flake.lock, input `paper`), so the PDFs are the ones `just paper`
  # makes. Keep this list the same as the lab's; newunicodechar is the one more package the video
  # script's metadata.md loads.
  tex = texliveMedium.withPackages (ps: with ps; [
    xetex fontspec unicode-math lm lm-math babel-english csquotes enumitem etoolbox fancyhdr
    footnotehyper titling xurl booktabs microtype xcolor upquote bookmark parskip newunicodechar
  ]);
  python = python3.withPackages (ps: [ ps.pillow ]);
in
stdenvNoCC.mkDerivation {
  pname = "proof-site";
  version = builtins.substring 0 7 rev;
  # The whole tree, except the vendored code that no page shows.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference ../. ../vendor;
  };
  nativeBuildInputs = [ python pandoc haskellPackages.pandoc-crossref tex ffmpeg ];
  # XeLaTeX finds DejaVu Sans, which the video script sets its symbols in, through fontconfig.
  FONTCONFIG_FILE = makeFontsConf { fontDirectories = [ dejavu_fonts ]; };

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR TEXMFVAR=$TMPDIR/texmf-var
    # The preview finds its typeface in ~/.fonts (roteiro-preview/preview.py, FONT_DIRS).
    mkdir -p $HOME/.fonts && cp ${dejavu_fonts}/share/fonts/truetype/DejaVuSans*.ttf $HOME/.fonts/
    python3 site/build.py --out $TMPDIR/site --rev ${lib.escapeShellArg rev} \
      ${lib.optionalString (stamp != null) "--stamp ${lib.escapeShellArg stamp}"}
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    cp -R $TMPDIR/site $out
    runHook postInstall
  '';
  dontFixup = true;
  allowedReferences = [ ];
}
