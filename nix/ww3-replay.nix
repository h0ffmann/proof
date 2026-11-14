# The shell of milestone M5 (`nix develop .#ww3-replay`): WAVEWATCH III at the pin of
# ocean-triton/PLAN.md, built unchanged by its own CMake with the switch of the regression test
# ww3_ts1 (ST4), and the compilers and libraries that ww3-replay/ww3_capture.F90 links with.
# WW3_HOME is the build: bin/ (ww3_grid, ww3_strt, ww3_shel), lib/libww3.a and mod/ (its Fortran
# modules); WW3_SRC is the source, for the regression test's inputs. Every version comes from
# flake.lock's nixpkgs, and the source from the commit below.
{ pkgs }:
let
  rev = "92e2cf66af6e15ae80eb12562f2b05d4a2d75df5"; # tag 7.14.mos-92e2cf6
  # fetchGit with a rev is pure: the commit names the tree. (A fixed-output fetch of the archive
  # would do the same; the builder's sandbox here has no network, the evaluator has.)
  src = builtins.fetchGit {
    url = "https://github.com/metocean/WW3";
    inherit rev;
    shallow = true;
  };
  switch = "NOGRB SHRD PR0 FLX0 LN1 ST4 NL1 BT1 DB1 TR0 BS0 IC0 IS0 REF0 WNT1 WNX1 CRT1 CRX1 O0 O1 O2 O3 O4 O5 O6 O7 O10 O11";
  ww3 = pkgs.stdenv.mkDerivation {
    pname = "ww3-ts1-st4";
    version = "7.14.mos-92e2cf6";
    inherit src;
    nativeBuildInputs = [ pkgs.cmake pkgs.gfortran ];
    buildInputs = [ pkgs.netcdf pkgs.netcdffortran pkgs.hdf5 pkgs.zlib pkgs.curl ];
    # ww3_ts1/input/switch_ST4 at the pin, written here so that a move of the pin that changes it
    # shows in this file.
    preConfigure = ''
      [ "$(tr -s ' \n' ' ' < regtests/ww3_ts1/input/switch_ST4 | sed 's/ $//')" = "${switch}" ] \
        || { echo "switch_ST4 changed at the pin" >&2; exit 1; }
      cp regtests/ww3_ts1/input/switch_ST4 switch_ts1
      cmakeFlagsArray+=("-DSWITCH=$PWD/switch_ts1")
    '';
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DNetCDF_C_INCLUDE_DIR=${pkgs.netcdf.dev or pkgs.netcdf}/include"
      "-DNetCDF_Fortran_INCLUDE_DIR=${pkgs.netcdffortran}/include"
    ];
    postInstall = ''
      mkdir -p $out/mod
      cp model/src/mod/*.mod $out/mod/
    '';
  };
in
pkgs.mkShell {
  packages = [ ww3 pkgs.gfortran pkgs.netcdf pkgs.netcdffortran pkgs.just pkgs.git ];
  WW3_HOME = ww3;
  WW3_SRC = src;
  WW3_LIBS = "-L${pkgs.netcdffortran}/lib -lnetcdff -L${pkgs.netcdf}/lib -lnetcdf";
  LANG = "C.UTF-8";
}
