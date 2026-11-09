# Z3

The invariants of the video script (`lean/ContextualBandit/Video.lean`) in a third form, after
the Haskell twin (`haskell/src/Video.hs`): an SMT check with Z3, in Python (`z3-solver`).

Lean proves each theorem for all values. `video.py` does the same by refutation: it asserts the
negation of each theorem and asks Z3 for a model. `unsat` means that no counterexample exists in
exact real arithmetic. The `#eval` values of the Lean file are checked as closed terms.

| In Lean | In Z3 | How |
|---|---|---|
| `clip_nonneg`, `clip_le_one`, `User.bounded` | the same names | negation unsat, for every real `x` and `target` |
| `step_exploit`, `step_explore_n`, `step_explore_reward`, `step_reward_bounded` | the same names | the approximation and the user's answer are symbolic reals |
| `epsGreedy_zero`, `epsGreedy_one_is_ab_test`, `etc_before`, `etc_after`, `etc_valid` | the same names | K = 3 arms, symbolic means and rounds |
| `rsi_valid`, `outer_explores` | the same names | M = 4 candidate ε, K = 3 inner arms, every ε symbolic |
| `leibnizPair_pos` | the same name | for every real `k ≥ 0` (Lean: every natural `k`) |
| `ramTerm_pos`, `ramSum_lt_succ` | the same names | for `k = 0 .. 9` only: Z3 has no factorial of a symbolic `k` |
| `ramApprox_anti` | the same name | symbolic `c`, `s_n`, `s_next` |
| the `#eval` lines | `leibniz 1, 2, 5`, `leibnizEven 2`, `ramSum 1`, `etc 10 3`, `etc 10 10`, `step` | closed terms, compared with the Lean output |

Run it:

```sh
just z3          # python3 z3/video.py
```

It needs `z3-solver` (`pip install z3-solver`, or `python3-z3` from the distribution; `nix
develop` has it). The exit code is 1 when an invariant fails.

## The PTC rules of the video script

The script's prose (`papers/contextual-bandits/script/prose-pt-BR/`) follows Português Técnico
Controlado (PTC, [kayquer/portugues-tecnico-controlado](https://github.com/kayquer/portugues-tecnico-controlado),
version 1.2.0), level `leve`, for a human reader (`00-como-ler.md`, lines 3 to 6). `ptc.py` takes
the part of each rule that a program can measure, measures it on every sentence, gives the values
to Z3 as constants and asks for a model of the negation of the rule. `unsat` means that no sentence
breaks it.

```sh
python3 z3/ptc.py --self-test   # each required check rejects a bad text and accepts a good one
python3 z3/ptc.py               # one line per check; exit code 1 if a required check fails
python3 z3/ptc.py --review      # also the sentences a person must read (the table below)
```

Code, file names, URLs, citation keys, quotations and italic foreign words are the protected zone
of PTC (its SKILL.md, "Processo", step 3) and are taken out first; a sentence keeps all its words
for the length check.

| Rule (level `leve`) | Required? | What Z3 checks | In `ptc.py` |
|---|---|---|---|
| PTC-5, sentence length | yes | every sentence has at most 35 words | `MAX_WORDS`, `words` |
| PTC-7, number, date, unit | yes | no decimal point (a scene, a version, an ISO month are not decimals), no `1,000,000`, no `DD/MM/YYYY`, no AM/PM, a space before a unit symbol, no symbol in the plural, no `10-20` range | `NUMBER_FORMAT`, `DECIMAL_POINT`, `NUMBER_ID` |
| PTC-8, spelling of 1990 | yes | the prefix and hyphen cases, the trema (not in a name), the open diphthong of a paroxytone, the abolished differential accents | `SPELLING`, `PREFIX_HYPHEN_VOWEL`, `TREMA` |
| PTC-9, chatbot noise | yes | no chatbot artefact, meta-text, model limit or generic conclusion | `NOISE_ALWAYS` |
| PTC-1, coreference (the pattern part) | yes | no mesoclisis, no 3rd-person enclitic (`enganá-la`), no `o mesmo` as a pronoun | `CLITIC`, `CLITIC_OK` |
| PTC-6, frozen names | yes (product and process names only) | one spelling for each name, no `API's`, the Brazilian variant | `FROZEN`, `frozen_hits` |
| PTC-9, filler and inflation | recommended | no filler, vague attribution, copula evasion, inflation or made contrast | `NOISE_FILLER` (a `NOTE`, not a failure) |
| sentences per paragraph | recommended | at most 6 | `MAX_SENTENCES` (a `NOTE`, not a failure) |

Off at level `leve` (the PTC level table), so not checked: PTC-1 passive `-se`, PTC-2 one
proposition per sentence and a fixed verb form, PTC-2 restrictive relatives, PTC-4 support verbs,
PTC-5 chains of `de`, the PTC-6 avoid-and-use lexicon, the vertical list.

### PTC rules that Z3 cannot prove

These need the meaning of the sentence, a parse or a dictionary, which no formula over the
measured values holds. `python3 z3/ptc.py --review` lists the sentences of the script that a
person must read for each one (the `REVIEW` list in `ptc.py`):

| Rule | Required at `leve`? | Why Z3 cannot decide it | Sentences listed by `--review` |
|---|---|---|---|
| PTC-1, a subject in every finite clause, no pronoun or demonstrative that points outside its sentence, no invented actor | yes | needs a parse and the referent of each pronoun | sentences that open with `Ele`, `Esse`, `Isso`, `Este`… |
| PTC-1, no proclitic 3rd-person pronoun (`que o sustenta`) | yes | `o` and `a` are also articles; only a parse tells them apart | `que`/`não`/`já`/`se` + `o`/`a` + a verb form |
| A condition opens the sentence | yes | the scope of `se`, `quando`, `caso` is syntax | sentences with one of them after a comma |
| PTC-6, one concept, one term | yes for names (checked above), off for the rest | a synonym is a matter of meaning; no list holds all of them | none |
| PTC-8, words outside the curated list | yes | needs the VOLP (Academia Brasileira de Letras), which has no API | none |
| PTC-9, a sentence that says nothing | yes for chatbot noise (checked above) | the PTC test is "what is lost if it goes?" | none |
| PTC-2, no gerund that joins two clauses | recommended | a gerund after `estar` is fine; only the meaning tells them apart | a gerund after a comma |
| PTC-3, one meaning per modal, no hedge | recommended | `deve` is obligation or probability, `pode` permission or capacity | sentences with a modal |
| PTC-5, adjective after the noun | recommended | needs a part-of-speech tag | `um simples`, `um único`, `a nova`… before a noun |
