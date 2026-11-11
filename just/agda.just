# Agda (agda/: the contextual bandit, the cycle clock, upwind advection, the grid size rules): the
# hygiene rule, a self-test, then every module type-checks (nix develop .#agda). Also in `just check`.
agda:
    bash checks/agda.sh --self-test
