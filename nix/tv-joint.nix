# The shell of tv-audience/python/joint_step.py (`nix develop .#tv-joint`): the packages of
# tv-audience/python/experiment.py, scikit-learn included, which XGBoost's scikit-learn interface
# and the MLP need and the data shell does not give.
{ pkgs }:
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (p: [ p.numpy p.pandas p.scipy p.scikit-learn p.xgboost ]))
  ];
}
