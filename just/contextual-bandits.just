# Contextual bandits: the text checks of the video script (tools/text-checks/) and the video script
# (contextual-bandits/script/). The bandit's theorems, examples and video invariants are proved in
# agda/src/ContextualBandit/ (`just agda`).

# Z3 through SBV (tools/text-checks/README.md has the details): the language rule (every file in
# English unless its path carries pt-BR), the PTC rules of the video script
# (`tools/text-checks/run.sh ptc --review` lists what Z3 cannot decide) and its PTC-9 noise
# catalogue. docs/decisions/0001-z3-over-lean.md says why Z3. Also in `just check`.
z3:
    bash checks/text-checks.sh

# The PTC-9 noise catalogue (references/ruido-ia.md of PTC) on the video script, row by row
# (`tools/text-checks/run.sh ruido-ia --review` lists the rows Z3 cannot decide)
ruido-ia:
    tools/text-checks/run.sh ruido-ia --self-test
    tools/text-checks/run.sh ruido-ia

# The video script (contextual-bandits/script/), a paper that lives in the bandit's folder and not
# under papers/, so `_pdf` gets its path relative to papers/. Its Brazilian Portuguese edition: pdf/contextual-bandits-script-pt-BR.pdf. Run inside `nix develop`.
script:
    mkdir -p build/tex pdf
    printf '%s+%s' "$(git rev-parse --short HEAD)" "$(git rev-list --count HEAD)" > build/.current-revision
    just _pdf ../contextual-bandits/script prose-pt-BR contextual-bandits-script-pt-BR

# In the pinned Manim shell; `just takes -q l 1.3 2.2` renders two takes at 480p.
# contextual-bandits/script/animation/README.md has the details.
# Render the video's Manim takes, one scene per take, into build/takes/take-N.M.mp4 (1080p)
takes *args:
    nix develop .#manim --command bash contextual-bandits/script/animation/render.sh {{args}}
