{
  description = "dogma: the paper toolchain comes from h0ffmann/picasso's paper lab (Paper Fabric)";

  # `nix flake update` picks up a new revision of the lab.
  inputs.paper.url = "github:h0ffmann/picasso?dir=labs/paper";

  outputs = { paper, ... }:
    let
      # One shell per feature: nix/<name>.nix is a function of { pkgs } and becomes
      # devShells.<name>, so a pull request that adds a shell does not edit this file.
      featureShells = pkgs:
        builtins.listToAttrs (map
          (file: {
            name = builtins.replaceStrings [ ".nix" ] [ "" ] file;
            value = import (./nix + "/${file}") { inherit pkgs; };
          })
          (builtins.filter (file: builtins.match ".*\\.nix" file != null)
            (builtins.attrNames (builtins.readDir ./nix))));
    in {
    # default: pandoc, pandoc-crossref, XeLaTeX, pdfLaTeX and just (the paper lab), plus Gleam on
    # Erlang for tools/ (refs-check, ste-check). md: the three Markdown analysers of
    # `just md-quality`. The others come from nix/<name>.nix. Everything comes from the paper
    # lab's nixpkgs, so flake.lock pins it all.
    devShells = builtins.mapAttrs
      (system: shells:
        let pkgs = paper.inputs.nixpkgs.legacyPackages.${system}; in featureShells pkgs // {
          default = pkgs.mkShell {
            inputsFrom = [ shells.default ];
            packages = [ pkgs.gleam pkgs.beamPackages.erlang pkgs.beamPackages.rebar3 ];
          };
          md = pkgs.mkShell { packages = [ pkgs.markdownlint-cli2 pkgs.vale pkgs.lychee ]; };
        })
      paper.devShells;
  };
}
