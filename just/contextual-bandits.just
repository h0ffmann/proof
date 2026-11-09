# Contextual bandits: the Z3 specification (z3-scala/) and the video script (papers/contextual-bandits/script/).

# Z3 (needs a JDK and sbt; z3-scala/z3.sh fetches Z3's Java binding): the contextual bandit's
# theorems, its examples, the video script's invariants, the language rule (every file in English
# unless its path carries pt-BR), the PTC rules of the video script (`z3-scala/z3.sh ptc --review`
# lists what Z3 cannot decide) and its PTC-9 noise catalogue. z3-scala/README.md has the details;
# docs/decisions/0001-z3-over-lean.md says why Z3. Also in `just check`.
z3:
    bash checks/contextual-bandits.sh

# The PTC-9 noise catalogue (references/ruido-ia.md of PTC) on the video script, row by row
# (`z3-scala/z3.sh ruido-ia --review` lists the rows Z3 cannot decide)
ruido-ia:
    z3-scala/z3.sh ruido-ia --self-test
    z3-scala/z3.sh ruido-ia

# The video script (papers/contextual-bandits/script/), a paper inside the paper's folder, in its
# Brazilian Portuguese edition: pdf/contextual-bandits-script-pt-BR.pdf. Run inside `nix develop`.
script:
    mkdir -p build/tex pdf
    printf '%s+%s' "$(git rev-parse --short HEAD)" "$(git rev-list --count HEAD)" > build/.current-revision
    just _pdf contextual-bandits/script prose-pt-BR contextual-bandits-script-pt-BR
