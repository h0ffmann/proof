# z3-scala: every Z3 check of this repository, in Scala

The Z3 checks of this repository are one Scala 3 application with two dependencies: Z3's official
Java binding (`com.microsoft.z3`, Z3 5.3.3) and Kyo, the effect system the checks run in. They were Python over `z3-solver` until 2026-11-09;
the port keeps every statement and gives the same output, line for line, except the
counterexamples of `chaceon` (below).

Every statement is proved by refutation (`kernel/proof/Proof.scala`): the premises and the negation of the
conclusion are asserted, and Z3 is asked for a model. `unsat` means that no counterexample exists
in exact real arithmetic. A model, when there is one, is printed: it is the counterexample.

```sh
z3-scala/z3.sh <check> [options]    # from the repository root; exit 1 when a statement fails
```

| Check | File | What it holds | Statements |
|---|---|---|---|
| (the method) | `kernel/proof/Proof.scala`, `kernel/smt/Z.scala` | `proves(name, premises, conclusion)`, `evaluates(name, term, rational)`, `counterexample`, `verdict` as values (`Item`), run by the `Prover`; Z3's Java API with operators, so a statement reads as its sentence | |
| (the definitions) | `bandit/domain/Bandit.scala` | the two layers: K estimates `(mean, width)` as Z3 reals; the rules `greedy`, `ucb(beta)`, `epsGreedy(eps)` built from `argmaxFirst` (ties to the first arm), `point`, `uniform`, `mix`; `valid`, `same` | |
| `theorems` | `bandit/domain/Theorems.scala` | validity of the three rules, `epsGreedy_prob`, `epsGreedy_explores`, `epsGreedy_one_is_ab_test`, `greedy_is_argmax`, `ucb_is_argmax`, `ucb_zero`, the optimism lemma `ucb_gap` under calibration, `greedy_gap`, `policy_factors` (an uninterpreted estimate function) | 60, for K = 1..5 |
| `examples` | `bandit/domain/Examples.scala` | the tabular model over exact rationals (`update`, `estimate`, `posterior`, `policy`) and the values the Haskell spec check reproduces | 9 |
| `video` | `bandit/domain/Video.scala` | the video script's invariants R1 to R5 (`papers/contextual-bandits/script/`): the user as reward, the one-armed agent, explore-then-commit as one rule, RSI as the same rule, the series of pi; and the examples of the spec check | 31 |
| `language` | `language/domain/LanguageRule.scala` | the language rule of `AGENTS.md`: every tracked text file is in English unless its path carries `pt-BR`, as `portuguese(f) <-> marked_pt_br(f)` | one per file |
| `ptc`, `ruido-ia` | `ptc/domain/Ptc.scala`, `ptc/domain/NoiseCatalogue.scala` | the PTC rules and the PTC-9 noise catalogue on the video script (below) | one per rule |
| `chaceon`, `coverage` | `portaudit/` | the audit of chaceon, the Rust port of WAVEWATCH III ([`port-audit/README.md`](../port-audit/README.md)) | 28; a table |
| `grids` | `grids/domain/Grids.scala` | the size rules of a triangle grid and WW3's explicit sub-step count ([`triangle-grids/README.md`](../triangle-grids/README.md)) | 13 |
| `leo` | `leo/` (domain, infrastructure, application), `z3-scala/leo/*.p` | higher-order statements proved by Leo-III (below) | 5 |

The Haskell spec check (`cabal run examples`, block 0) compares its values with `Examples.scala`
and `Video.scala`. It was a Lean 4 package until 2026-11-09; `docs/decisions/0001-z3-over-lean.md`
says why it moved to Z3, what the move cost, and the move to Scala.

What Z3 cannot do, and how it is bounded:

- **No induction over K.** Each theorem is checked for every K from 1 to `MAX_ARMS` (5) in
  `Bandit.scala`, for all real estimates. The rules are the same code for every K.
- **No factorial of a symbolic k.** The positivity of Ramanujan's terms is checked for k = 0 to 9
  in exact rationals; Leibniz's pairs hold for every real k >= 0.
- **No probability.** The probabilistic half of a regret bound (calibration with high
  probability, the sum of the widths) is not here, as it was not in Lean.
- **No quantifier over functions or sets.** That is higher-order logic: Leo-III's job (below).

## Build and run

Run it inside the root flake's shell, which pins every tool (`AGENTS.md`, "Reproducible builds"):

```sh
nix develop .#scala      # JDK 25, sbt, and Z3 with its Java binding (Z3_HOME), from flake.lock's nixpkgs
```

| What | Pinned in | Version |
|---|---|---|
| JDK | `flake.nix` (`jdk25_headless`) | 25.0.4.1 at the locked nixpkgs |
| Z3 and its Java binding | `build.sbt` (`z3Version`); `flake.nix` builds that tag with a fixed source hash | 5.3.3 |
| Scala | `build.sbt` (`scalaVersion`) | 3.9.0, the LTS line |
| Kyo (`kyo-core`) | `build.sbt` (`kyoVersion`), from Maven Central | 1.0.0-RC7, the latest release on 2026-11-09; compiled for Java 25 |
| sbt | `project/build.properties` (the flake's sbt launcher fetches it) | 2.0.12 |
| scalafmt, scalafix | `project/plugins.sbt`, `.scalafmt.conf` | sbt-scalafmt 2.6.2 (scalafmt 3.11.5), sbt-scalafix 0.14.10 |

`z3.sh` does the rest:

1. **Z3.** Z3 ships its Java binding in its release archives, not on Maven, so no resolver fetches
   it. The first run puts it in place: `lib/com.microsoft.z3.jar` and the native libraries in
   `.z3/`. They come from `Z3_HOME`, which the Nix shell sets, or else, outside the shell, from the
   `z3-<z3Version>` release on GitHub for this platform, checked against the SHA-256 that GitHub
   publishes for the asset. ⚠ The release download was not tested: the machine this was written
   on cannot reach GitHub's release files.
2. **The build.** `build.sbt` names the jar as its unmanaged dependency and stops when it is
   missing, and takes Kyo from Maven Central; `Main` stops when the Z3 it loads (`com.microsoft.z3.Version`) is not `z3Version`. The
   settings follow [marola-dev/marola-app](https://github.com/marola-dev/marola-app) with the
   current plugin versions. The classpath is cached in `target/classpath` and rebuilt when a
   source is newer.
3. **The run.** `java -cp <classpath> z3scala.app.main <check>`, from the repository root, with
   standard output and error in UTF-8 whatever the locale.

```sh
just z3        # theorems, examples, video, language, ptc, ruido-ia (checks/contextual-bandits.sh)
just port-audit
just grids
just leo
cd z3-scala && sbt scalafmtCheckAll "scalafixAll --check"   # the format and the lint rules
```

The compiler holds the style. `-new-syntax` refuses the braces and parentheses of Scala 2's
control syntax, and `-Werror` turns every warning into an error, with `-Wunused`, `-Wvalue-discard`,
`-Wnonunit-statement` and `-language:strictEquality` on. scalafmt (`removeOptionalBraces`) keeps the
indentation syntax everywhere else; scalafix forbids `return` and `null` and removes unused imports.
Identifiers are camelCase; the names of the Z3 statements and symbols did not change, so a report
reads as before.

**One difference from the Python output.** `chaceon` prints the same 28 verdicts, but a
counterexample is any model Z3 finds: the Java binding finds other witnesses than z3py did, and
prints a function interpretation inside a model in its own notation. The verdicts are the evidence; the witnesses are examples.

## Layout

The sources follow domain-driven design: a shared kernel, and one bounded context per family of
checks. A context's `domain` is pure: it builds its statements as values (`Vector[Item]`) or its
report as lines and an exit code (`Report`), from texts it is given. Its `application` reads what
the domain needs, calls it and prints the result. Its `infrastructure`, where it has one, is the
outside world that only it uses (the pins of `portaudit`, the Leo-III process). Kyo runs the
application: reading a file, running git or java and printing are `Sync` effects, and a failure
(a missing file, a git error, a stale README) is an `Abort[Failure]` that `app/Cli.scala` turns
into a message on standard error and its exit code.

```
src/main/scala/
  kernel/smt/              Z.scala (the Z3 vocabulary), Rational.scala
  kernel/proof/            Proof.scala (Item, Script, Prover: refutation, the tally in a Kyo Var), Report.scala
  kernel/text/             Py.scala (Python-compatible text: regexes, splitlines, formats), Json.scala
  kernel/infrastructure/   Host.scala (files, processes, environment, console as Kyo effects; Failure)
  bandit/                  domain: Bandit, Theorems, Examples, Video; application: BanditChecks
  language/                domain: LanguageRule; application: LanguageCheck (git ls-files)
  ptc/                     domain: Ptc, NoiseCatalogue; application: PtcChecks (the script's Markdown)
  portaudit/               domain: Chaceon, Coverage (Sources); infrastructure: Pins; application: PortAudit
  grids/                   domain: Grids; application: GridsCheck
  leo/                     domain: Problem; infrastructure: Leo3; application: LeoCheck
  app/                     Cli.scala (check names, exit codes 0, 1, 2, 64), Main.scala (the Z3 version check)
```

`Main` is not a `KyoApp`, because a `KyoApp` exits with 1 on any error and the checks have their
own exit codes; it runs the Kyo computation once, at the edge of the program.

## Higher-order statements: Leo-III

[Leo-III](https://github.com/leoprover/Leo-III) is an automated theorem prover for classical
higher-order logic with Henkin semantics and choice, by Christoph Benzmüller, Alexander Steen, Max
Wisniewski and others (Steen and Benzmüller, "Extensional Higher-Order Paramodulation in Leo-III",
*Journal of Automated Reasoning* 65, 775-807, 2021, [arXiv:1907.11501](https://arxiv.org/abs/1907.11501);
cite Leo-III as [10.5281/zenodo.4435994](https://doi.org/10.5281/zenodo.4435994); BSD-3-Clause).
It is written in Scala 3.9.0, the version of this build. Z3 decides first-order theories; a
statement that quantifies over functions or sets is outside them, and Leo-III proves it.

Leo-III publishes no jar for its current version (1.8.1; the last release tag is v1.7.18, on Scala
2.13), so `z3.sh` builds it with sbt from `leoprover/Leo-III` at commit `d24be031` (26 October
2026) into `.leo/` on the first `leo` run, unless `LEO3_JAR` names a jar. It runs as its own
process, as TPTP provers are called, and its SZS status line is the verdict.

Each problem is a TPTP THF file in `leo/`; its first line says what is expected:

| Problem | Statement | Expected | Result, 10 s limit |
|---|---|---|---|
| `cantor.p` | no function from a type onto the sets of that type | Theorem | Theorem, under 1 s |
| `choice_inverse.p` | a surjective function has a right inverse (needs choice) | Theorem | Theorem |
| `composition.p` | function composition is associative (needs extensionality) | Theorem | Theorem |
| `belief.p` | a policy that is a function of the belief gives two histories with the same belief the same action, for every belief map: `policy_factors` of `Theorems.scala` with the functions quantified, where Z3 used one uninterpreted function | Theorem | Theorem |
| `surjective_not_injective.p` | a surjective function is injective: false | not Theorem | Timeout |

Leo-III builds no countermodel, so a false statement ends in `Timeout` or `GaveUp`, and the check
asks only that it is not proved. Knaster-Tarski for monotone maps on sets was tried and timed out
at 30 s, with and without `--primsubst 5`; it is not in the list.

```sh
z3-scala/z3.sh leo        # 10 s per problem
z3-scala/z3.sh leo 30     # another limit
```

## The PTC rules of the video script

The script's prose (`papers/contextual-bandits/script/prose-pt-BR/`) follows Português Técnico
Controlado (PTC, [kayquer/portugues-tecnico-controlado](https://github.com/kayquer/portugues-tecnico-controlado),
version 1.2.0), level `leve`, for a human reader (`00-como-ler.md`, lines 3 to 6). `ptc/domain/Ptc.scala` takes
the part of each rule that a program can measure, measures it on every sentence, gives the values
to Z3 as constants and asks for a model of the negation of the rule. `unsat` means that no sentence
breaks it.

```sh
z3-scala/z3.sh ptc --self-test   # each required check rejects a bad text and accepts a good one
z3-scala/z3.sh ptc               # one line per check; exit code 1 if a required check fails
z3-scala/z3.sh ptc --review      # also the sentences a person must read (the table below)
```

Code, file names, URLs, citation keys, quotations and italic foreign words are the protected zone
of PTC (its SKILL.md, "Processo", step 3) and are taken out first; a sentence keeps all its words
for the length check.

| Rule (level `leve`) | Required? | What Z3 checks | In `ptc/domain/Ptc.scala` |
|---|---|---|---|
| PTC-5, sentence length | yes | every sentence has at most 35 words | `MAX_WORDS`, `words` |
| PTC-7, number, date, unit | yes | no decimal point (a scene, a version, an ISO month are not decimals), no `1,000,000`, no `DD/MM/YYYY`, no AM/PM, a space before a unit symbol, no symbol in the plural, no `10-20` range | `NUMBER_FORMAT`, `DECIMAL_POINT`, `NUMBER_ID` |
| PTC-8, spelling of 1990 | yes | the prefix and hyphen cases, the trema (not in a name), the open diphthong of a paroxytone, the abolished differential accents | `SPELLING`, `PREFIX_HYPHEN_VOWEL`, `TREMA` |
| PTC-9, chatbot noise | yes | no chatbot artefact, meta-text, model limit or generic conclusion | `NOISE_ALWAYS` |
| PTC-1, coreference (the pattern part) | yes | no mesoclisis, no 3rd-person enclitic (`enganá-la`), no `o mesmo` as a pronoun | `CLITIC`, `CLITIC_OK` |
| PTC-6, frozen names | yes (product and process names only) | one spelling for each name, no `API's`, the Brazilian variant | `FROZEN`, `frozenHits` |
| PTC-9, filler and inflation | recommended | no filler, vague attribution, copula evasion, inflation or made contrast | `NOISE_FILLER` (a `NOTE`, not a failure) |
| sentences per paragraph | recommended | at most 6 | `MAX_SENTENCES` (a `NOTE`, not a failure) |

Off at level `leve` (the PTC level table), so not checked: PTC-1 passive `-se`, PTC-2 one
proposition per sentence and a fixed verb form, PTC-2 restrictive relatives, PTC-4 support verbs,
PTC-5 chains of `de`, the PTC-6 avoid-and-use lexicon, the vertical list.

### PTC rules that Z3 cannot prove

These need the meaning of the sentence, a parse or a dictionary, which no formula over the
measured values holds. `z3-scala/z3.sh ptc --review` lists the sentences of the script that a
person must read for each one (the `REVIEW` list in `ptc/domain/Ptc.scala`):

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

`ptc/domain/NoiseCatalogue.scala` checks the catalogue of PTC-9 itself, `references/ruido-ia.md` of
[kayquer/portugues-tecnico-controlado](https://github.com/kayquer/portugues-tecnico-controlado/blob/main/references/ruido-ia.md),
on the same sentences as `ptc/domain/Ptc.scala` (it uses its reader). Each row of a table of the catalogue is one
row of `CATALOGUE`. For a row that Z3 decides, every sentence gets a constant `h[row][sentence]`,
the number of hits, and Z3 is asked for a model of "some `h` > 0". The forms that the catalogue's
"O que fica" keeps (`estimador robusto`, `teorema fundamental`, `estado fundamental`,
`proxy transparente`, and `Contamos com vocês` at `leve`) are not hits, and a vague attribution
with a citation key or a URL in its sentence is not a hit.

```sh
just ruido-ia                          # --self-test, then the check at level leve (also in just check
                                       # and in the manual check workflow)
z3-scala/z3.sh ruido-ia --review       # also the rows a person must read, with their sentences
z3-scala/z3.sh ruido-ia --level estrito # the same tables at another level
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
chained gerund is PTC-2, both in `ptc --review`.
