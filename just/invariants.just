# The repository's standing rules, as an answer set program: Invariants.lp, solved by clingo on the
# facts that tools/invariants/ reads from the tree. Also in `just check`.
invariants:
    bash checks/invariants.sh

# Print the facts that Invariants.lp is solved with
invariants-facts:
    tools/invariants/run.sh --facts
