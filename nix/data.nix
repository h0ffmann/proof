# The data shell (`nix develop .#data`): Python with the packages of the numerical experiments,
# fat-tails/python (NumPy, pandas, SciPy, Matplotlib) and tv-audience/python (also XGBoost);
# crypto-strength/build.py needs the standard library only.
{ pkgs }:
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (p: [ p.numpy p.pandas p.scipy p.matplotlib p.xgboost ]))
    pkgs.just
    pkgs.git
  ];
}
