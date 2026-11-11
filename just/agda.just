# The contextual bandit in Agda (agda/): the hygiene rule, a self-test, then every module
# type-checks (nix develop .#agda). Also in `just check`.
agda:
    bash checks/agda.sh --self-test
