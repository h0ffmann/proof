# The browsable index of proof (site/): index.html, the preprints as PDF, the pages as HTML, the video
# script's preview and the diagrams, built by Nix with the nixpkgs of flake.lock into result-site/.
# Built from the tracked files at the current commit; a dirty tree links to main. site/README.md has the details.
site:
    nix build --extra-experimental-features 'nix-command flakes' --impure -L -o result-site --expr \
      'let f = builtins.getFlake ("git+file://" + toString ./.); pkgs = f.inputs.paper.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}; in pkgs.callPackage "${f}/site" { rev = f.rev or "main"; stamp = (f.shortRev or f.dirtyShortRev or "unversioned") + (if f ? revCount then "+${toString f.revCount}" else ""); }'
    @echo "site: result-site/index.html"

# Serve result-site/ at http://localhost:8000 (`just site` first)
site-serve port="8000":
    python3 -m http.server {{port}} --directory result-site
