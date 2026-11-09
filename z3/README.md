# Z3: the specification of the contextual bandit

The contextual bandit is specified here, in Python over Z3 (`z3-solver`), and ported to Haskell in
`haskell/`. Every statement is proved by refutation (`refute.py`): the premises and the negation of
the conclusion are asserted, and Z3 is asked for a model. `unsat` means that no counterexample
exists in exact real arithmetic. A model, when there is one, is printed: it is the counterexample.
It was a Lean 4 package until 2026-11-09; `docs/decisions/0001-z3-over-lean.md` says why it moved
and what the move cost.

| File | What it holds | Statements |
|---|---|---|
| `refute.py` | `proves(name, premises, conclusion)`, `evaluates(name, term, rational)`, `finish()` | the method |
| `bandit.py` | the two layers: K estimates `(mean, width)` as Z3 reals; the rules `greedy`, `ucb(beta)`, `eps_greedy(eps)` built from `argmax_first` (ties to the first arm), `point`, `uniform`, `mix`; `valid`, `same` | the definitions |
| `theorems.py` | validity of the three rules, `epsGreedy_prob`, `epsGreedy_explores`, `epsGreedy_one_is_ab_test`, `greedy_is_argmax`, `ucb_is_argmax`, `ucb_zero`, the optimism lemma `ucb_gap` under calibration, `greedy_gap`, `policy_factors` (an uninterpreted estimate function) | 60, for K = 1..5 |
| `examples.py` | the tabular model over exact rationals (`update`, `estimate`, `posterior`, `policy`) and the values the Haskell spec check reproduces | 9 |
| `video.py` | the video script's invariants R1 to R5 (`papers/contextual-bandits/script/`): the user as reward, the one-armed agent, explore-then-commit as one rule, RSI as the same rule, the series of pi; and the examples of the spec check | 31 |
| `language.py` | the language rule of `AGENTS.md`: every tracked text file is in English unless its path carries `pt-BR`, as `portuguese(f) <-> marked_pt_br(f)` | one per file |

What Z3 cannot do, and how it is bounded:

- **No induction over K.** Each theorem is checked for every K from 1 to `MAX_ARMS` (5) in
  `bandit.py`, for all real estimates. The rules are the same code for every K.
- **No factorial of a symbolic k.** The positivity of Ramanujan's terms is checked for k = 0 to 9
  in exact rationals; Leibniz's pairs hold for every real k >= 0.
- **No probability.** The probabilistic half of a regret bound (calibration with high
  probability, the sum of the widths) is not here, as it was not in Lean.

Run it:

```sh
just z3          # theorems, examples, video, language, ptc, ruido_ia (checks/contextual-bandits.sh); exit 1 on FAIL
```

It needs `z3-solver` (`pip install z3-solver`, or `python3-z3` from the distribution). The Haskell
spec check (`cabal run examples`, block 0) compares its values with `examples.py` and `video.py`.

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

## The PTC-9 noise catalogue

`ruido_ia.py` checks the catalogue of PTC-9 itself, `references/ruido-ia.md` of
[kayquer/portugues-tecnico-controlado](https://github.com/kayquer/portugues-tecnico-controlado/blob/main/references/ruido-ia.md),
on the same sentences as `ptc.py` (it uses its reader). Each row of a table of the catalogue is one
row of `CATALOGUE`. For a row that Z3 decides, every sentence gets a constant `h[row][sentence]`,
the number of hits, and Z3 is asked for a model of "some `h` > 0". The forms that the catalogue's
"O que fica" keeps (`estimador robusto`, `teorema fundamental`, `estado fundamental`,
`proxy transparente`, and `Contamos com vocês` at `leve`) are not hits, and a vague attribution
with a citation key or a URL in its sentence is not a hit.

```sh
just ruido-ia                          # --self-test, then the check at level leve (also in just check
                                       # and in the manual check workflow)
python3 z3/ruido_ia.py --review        # also the rows a person must read, with their sentences
python3 z3/ruido_ia.py --level estrito # the same tables at another level
```

| Table | At `leve` | Rows Z3 decides | Result on the script |
|---|---|---|---|
| Sempre sai | required (`FAIL`) | 10 | unsat |
| Enchimento | recommended (`NOTE`) | 9 | unsat |
| Evasão de cópula | off (`OFF`, shown only) | 3 | unsat |
| Inflação | off (`OFF`, shown only) | 4 | unsat |

The script also gives `unsat` for all four tables at `estrito`.

### Rows that Z3 cannot decide

Their "Evite" cell has a qualifier that is meaning, not text. `--review` lists the sentences that
carry the phrase:

| Table | Row | Why Z3 cannot decide it | Sentences on the script |
|---|---|---|---|
| Sempre sai | `Vamos` + a verb that the table does not name | whether the opening delays the subject is meaning; 1st person is allowed at `leve` | `01-cmab.md:59`, `03-rsi.md:25`, `03-rsi.md:61` |
| Enchimento | `além disso` / `ademais` / `outrossim` inside a sentence | the connector may add a real second item | none |
| Enchimento | `nesse sentido` / `dessa forma` / `desse modo` (no causal relation) | "O que fica" keeps a real consequence; causality is meaning | none |
| Evasão de cópula | `apresenta` (in the sense of `tem`) | `apresentar erro` is another sense | none |
| Evasão de cópula | `representa` (in the sense of `é`) | a symbol that stands for a thing is not a copula | none |
| Inflação | `robusto` (vague praise) | `estimador robusto` is a term | none |
| Inflação | `abrangente` / `completo` (without the scope) | out only when the text does not say what it covers | `03-rsi.md:103`, `03-rsi.md:126` |
| Inflação | `transparente` / `fluido` | `proxy transparente` is a term, `fluido` can be physics | none |
| Inflação | `crucial` / `fundamental` / `essencial` / `primordial` (as emphasis) | `teorema fundamental` is a term | none |
| Inflação | `transformador` | a transformer is a thing | none |
| Inflação | `ecossistema` (metaphor) | an ecosystem in biology is literal | none |
| Inflação | `não é só X, é Y` (made contrast) | made only if nobody said it was only X | `01-cmab.md:101` |

The verb row `alavancar` / `potencializar` / `impulsionar` is decided on the verb forms only:
`alavanca` is also the noun, the lever of a bandit, which the script uses. The last section of the
catalogue, "O que não veio da deai-text", adds no row: the rotation of synonyms is PTC-6 and the
chained gerund is PTC-2, both in `ptc.py --review`.
