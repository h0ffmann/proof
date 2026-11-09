# The Lean shell (`nix develop .#lean`): the Lean release that the packages' lean-toolchain files
# name (ocean-waves/lean, cycle/lean, house-pricing/lean), from its GitHub release with a fixed
# hash per platform, so no step downloads a toolchain. lean, lake and leanc come from the same
# release; `lake build` runs as with elan. A new release changes the three lean-toolchain files
# together and the four hashes below; a stale hash stops the build, and files that disagree stop
# the evaluation.
{ pkgs }:
let
  toolchain = dir: builtins.head (builtins.match "leanprover/lean4:v([^[:space:]]+)[[:space:]]*"
    (builtins.readFile (../. + "/${dir}/lean-toolchain")));
  versions = map toolchain [ "ocean-waves/lean" "cycle/lean" "house-pricing/lean" ];
  version = builtins.head versions;
  release = {
    x86_64-linux = { asset = "linux"; hash = "sha256-sU9eUVkhndGhlWw7gGgTMZ9elMzVvf1W9UUgYJpbtew="; };
    aarch64-linux = { asset = "linux_aarch64"; hash = "sha256-I3+O9D+0DRZoGHH7BLLFbwI6/AKlo4d4MdNd1JOCPCM="; };
    x86_64-darwin = { asset = "darwin"; hash = "sha256-pe8PsOFGReqg5gvGujmgfn3u7sc9yTznGVuDfrneLJ8="; };
    aarch64-darwin = { asset = "darwin_aarch64"; hash = "sha256-F+5VRwLBmfwD83scNwgkVnHJP12TLc/1WgP6bNteWt8="; };
  }.${pkgs.stdenv.hostPlatform.system};
  lean = assert pkgs.lib.assertMsg (pkgs.lib.all (v: v == version) versions)
    "the lean-toolchain files name different releases: ${toString versions}";
    pkgs.stdenv.mkDerivation {
      pname = "lean4";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://github.com/leanprover/lean4/releases/download/v${version}/lean-${version}-${release.asset}.tar.zst";
        inherit (release) hash;
      };
      # The release is built for any Linux; on Linux its ELF files are pointed at Nix's loader and libraries.
      nativeBuildInputs = [ pkgs.zstd ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
      buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
      dontConfigure = true;
      dontBuild = true;
      dontStrip = true;
      installPhase = ''
        mkdir -p $out
        cp -r . $out
      '';
      meta = pkgs.lean4.meta // { platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]; };
    };
in
pkgs.mkShell {
  packages = [ lean pkgs.just pkgs.git ];
  passthru = { inherit lean; };
}
