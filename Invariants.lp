% Invariants.lp: the standing rules of this repository, as an answer set program (clingo 5.8).
%
% scripts/invariants.py reads the tree and the branch, writes what it sees as facts, and solves
% them with this file. Each rule below derives violation(Rule, Subject) when the tree breaks it.
% The check fails when a violation is not waived. A gap(Rule, Subject) is a rule that the tree
% does not keep yet; it is printed, but it does not fail the check. A waiver that excuses nothing
% fails the check too, so the list of waivers stays true.
%
%   just invariants               # check the tree; exit 1 on a violation
%   just invariants-self-test     # bad facts must give each violation
%
% Facts from scripts/invariants.py (strings are paths, names or words):
%   file(P)                      a tracked file
%   lean(P), lean_examples(P)    a tracked .lean file outside vendor/, and one named Examples.lean
%   lean_token(P, L, T)          line L of P has T in {sorry, admit, axiom, native_decide}
%   lean_package(D)              D has a lakefile.toml or lakefile.lean
%   lean_pinned(D)               D has a lean-toolchain file
%   pdf(P)                       P ends in .pdf
%   commit(C)                    a commit on this branch that main does not have
%   commit_trailer(C, T)         C has trailer or footer T (lower case)
%   commit_pair(C, A, B)         C has the token A/B; commit_issue_ref(C, A, B) has A/B#N
%   commit_url(C, A, B)          C has a link to github.com/A/B
%   branch(B), branch_part(B, W) the branch and each word of its name
%   flake_input_locked(I)        flake.lock pins input I to a revision
%   nix_package(P)               flake.nix, or a nix/*.nix shell it discovers, names pkgs.P
%                                (also P without its version: jdk25 gives jdk)
%   nix_shells_discovered        flake.nix makes a shell of each nix/<name>.nix
%   just_import(F), just_file(F) the justfile imports F; F is a tracked just/*.just
%   check_script(F), strict(F)   F is checks/*.sh; F sets -euo pipefail
%   workflow_trigger(W, T)       workflow W runs on T (triggers in comments are not counted)
%   cabal_package(N), cabal_dep(P, D)  a cabal package and each package that P depends on
%   build_pin(T, V)              a toolchain pinned outside Nix: lean, scala, sbt

% ── who we are, and the vocabulary ──────────────────────────────────────
self("h0ffmann", "proof").
owner("h0ffmann"). owner("piabrota"). owner("marola-dev").

attribution("co-authored-by"). attribution("claude-session"). attribution("signed-off-by").
attribution("generated with"). attribution("requested by").

session_word("claude"). session_word("session"). session_word("thread"). session_word("cmsg").

lean_hole(sorry). lean_hole(admit). lean_hole(axiom).

haskell_dep_allowed("base"). haskell_dep_allowed("containers").
% LiquidHaskell checks refinements written in comments; its plugin is allowed in a build.
haskell_dep_allowed("liquidhaskell"). haskell_dep_allowed("liquid-prelude"). haskell_dep_allowed("liquid-base").
haskell_dep_allowed(N) :- cabal_package(N).

% ── 1. Composable pull requests ─────────────────────────────────────────
% A feature keeps its recipes in just/<feature>.just and the justfile imports each one with
% `import?`. An import of a missing file, or a just file that nothing imports, breaks it.
violation(just_import_missing, F) :- just_import(F), not just_file(F).
violation(just_file_not_imported, F) :- just_file(F), not just_import(F).
% scripts/checks.sh runs every checks/<feature>.sh; each one stops at its first error.
violation(check_not_strict, F) :- check_script(F), not strict(F).

% ── 2. No other repository named in a commit, no attribution ───────────
mentions_other(C, A, B) :- commit_pair(C, A, B), owner(A), not self(A, B).
mentions_other(C, A, B) :- commit_issue_ref(C, A, B), not self(A, B).
mentions_other(C, A, B) :- commit_url(C, A, B), not self(A, B).
violation(commit_mentions_repo, (C, A, B)) :- mentions_other(C, A, B).
violation(commit_attribution, (C, T)) :- commit_trailer(C, T), attribution(T).

% ── 3. Branches are named by the goal ───────────────────────────────────
violation(branch_named_by_session, B) :- branch(B), branch_part(B, W), session_word(W).

% ── 4. Nix at the root pins the toolchains ──────────────────────────────
violation(no_root_flake, "flake.nix") :- not file("flake.nix").
violation(no_root_lock, "flake.lock") :- file("flake.nix"), not file("flake.lock").
violation(flake_input_unlocked, "paper") :- file("flake.lock"), not flake_input_locked("paper").

% What the tree needs, and the nixpkgs attribute that would pin it.
needs(ghc) :- file(P), cabal_dep(P, _).
needs(jdk) :- file("z3-scala/build.sbt").
needs(scala) :- file("z3-scala/build.sbt").
needs(z3) :- file("z3-scala/build.sbt").
needs(lean) :- lean_package(_).
needs(clingo).
needs(rust) :- file("house-pricing/rust/Cargo.toml").
needs(node) :- file("vendor/archify/package.json").
needs(zig) :- file("pomodoro/pomodoro.zig").
needs(ffmpeg) :- file(".claude/skills/roteiro-preview/preview.py").
in_nix(ghc) :- nix_package("ghc").
in_nix(ghc) :- nix_package("haskellPackages").
in_nix(ghc) :- nix_package("haskell").
in_nix(jdk) :- nix_package("jdk").
in_nix(jdk) :- nix_package("openjdk").
in_nix(jdk) :- nix_package("temurin").
in_nix(jdk) :- nix_package("zulu").
in_nix(scala) :- nix_package("sbt").
in_nix(scala) :- nix_package("scala").
in_nix(scala) :- nix_package("scala_3").
in_nix(scala) :- nix_package("scala-cli").
in_nix(z3) :- nix_package("z3").
in_nix(lean) :- nix_package("elan").
in_nix(lean) :- nix_package("lean4").
in_nix(clingo) :- nix_package("clingo").
in_nix(rust) :- nix_package("cargo").
in_nix(node) :- nix_package("nodejs").
in_nix(zig) :- nix_package("zig").
in_nix(ffmpeg) :- nix_package("ffmpeg").
in_nix(ffmpeg) :- nix_package("ffmpeg-headless").
% Pinned in the tree, but not by Nix: a gap, until flake.nix gives the tool.
gap(toolchain_not_in_nix, T) :- needs(T), not in_nix(T).
% Every Lean package pins its toolchain, Nix or not.
violation(lean_toolchain_unpinned, D) :- lean_package(D), not lean_pinned(D).

% ── 5. Every Lean proof is complete (AGENTS.md, rule 1) ─────────────────
violation(lean_hole, (P, L, T)) :- lean_token(P, L, T), lean_hole(T).
violation(native_decide_outside_examples, (P, L)) :-
    lean_token(P, L, native_decide), not lean_examples(P).

% ── 6. Haskell stays dependency-light (AGENTS.md, rule 6) ───────────────
violation(haskell_dependency, (P, D)) :- cabal_dep(P, D), not haskell_dep_allowed(D).

% ── 7. CI is off: workflows run only by hand ────────────────────────────
violation(workflow_runs_by_itself, (W, T)) :- workflow_trigger(W, T), T != "workflow_dispatch".

% ── 8. No PDF is committed (AGENTS.md, "Papers") ────────────────────────
violation(pdf_committed, P) :- file(P), pdf(P).

% ── Waivers: each one names what it excuses and why ─────────────────────
% These two PDFs were committed before the rule. Remove the line when the PDF leaves the tree.
waived(pdf_committed, "papers/fat-tails/fat-tails.pdf").
waived(pdf_committed, "papers/tv-audience/tv-audience.pdf").
% The owner asked for this one as a file (2026-11-11): its source is not in this repository.
waived(pdf_committed, "papers/practice-beats-theory/wave-models-on-gpus.pdf").

failing(R, S) :- violation(R, S), not waived(R, S).
stale_waiver(R, S) :- waived(R, S), not violation(R, S).

#show failing/2.
#show gap/2.
#show stale_waiver/2.
