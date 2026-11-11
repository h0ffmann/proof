# Agda (agda/: the contextual bandit, the cycle clock, the ocean-wave kernels, the Z3 checks): the
# hygiene rule, a self-test, then every module type-checks (nix develop .#agda). Also in `just check`.
agda:
    bash checks/agda.sh --self-test
