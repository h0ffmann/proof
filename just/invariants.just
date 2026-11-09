# The repository's standing rules, as an answer set program: Invariants.lp, solved by clingo on the
# facts that scripts/invariants.py reads from the tree. Also in `just check`.
invariants:
    bash checks/invariants.sh

# Print the facts that Invariants.lp is solved with
invariants-facts:
    python3 scripts/invariants.py --facts
