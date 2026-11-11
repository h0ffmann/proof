# The Agda shell (`nix develop .#agda`): Agda and its standard library for agda/ (the contextual
# bandit, `just agda`). Both come from the nixpkgs that flake.lock pins; the versions below are
# written here so that a bump of the lock that moves either one stops the evaluation, and the bump
# is made on purpose: change the version here and run `just agda` again.
{ pkgs }:
let
  agdaVersion = "2.8.0";
  stdlibVersion = "2.3";
  stdlib = pkgs.agdaPackages.standard-library;
  agda = assert pkgs.lib.assertMsg (pkgs.agda.version == agdaVersion)
    "nix/agda.nix pins Agda ${agdaVersion}, the locked nixpkgs gives ${pkgs.agda.version}";
    assert pkgs.lib.assertMsg (stdlib.version == stdlibVersion)
      "nix/agda.nix pins the standard library ${stdlibVersion}, the locked nixpkgs gives ${stdlib.version}";
    pkgs.agda.withPackages (_: [ stdlib ]);
in
pkgs.mkShell {
  packages = [ agda pkgs.just pkgs.git ];
  LANG = "C.UTF-8";
  passthru = { inherit agda; };
}
