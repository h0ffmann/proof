# Contextual bandits: the Z3 specification (z3/) and the video script (papers/contextual-bandits/script/).

# Z3 (needs python3 with z3-solver): the contextual bandit's theorems (z3/theorems.py), its examples
# (z3/examples.py), the video script's invariants (z3/video.py), the language rule, every file in
# English unless its path carries pt-BR (z3/language.py), the PTC rules of the video script (z3/ptc.py;
# `python3 z3/ptc.py --review` lists what Z3 cannot decide) and its PTC-9 noise catalogue
# (z3/ruido_ia.py). docs/decisions/0001-z3-over-lean.md says why Z3. Also in `just check`.
z3:
    bash checks/contextual-bandits.sh

# The PTC-9 noise catalogue (references/ruido-ia.md of PTC) on the video script, row by row
# (z3/ruido_ia.py; `python3 z3/ruido_ia.py --review` lists the rows Z3 cannot decide)
ruido-ia:
    python3 z3/ruido_ia.py --self-test
    python3 z3/ruido_ia.py

# The video script (papers/contextual-bandits/script/), a paper inside the paper's folder, in its
# Brazilian Portuguese edition: pdf/contextual-bandits-script-pt-BR.pdf. Run inside `nix develop`.
script:
    mkdir -p build/tex pdf
    printf '%s+%s' "$(git rev-parse --short HEAD)" "$(git rev-list --count HEAD)" > build/.current-revision
    just _pdf contextual-bandits/script prose-pt-BR contextual-bandits-script-pt-BR
