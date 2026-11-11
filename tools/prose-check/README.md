# tools/prose-check: the prose checks, in Agda

Writing standard: ASD-STE100.

This tool applies the rules of ASD-STE100 (Simplified Technical English, STE) and the rules of PTC
(português técnico controlado) that a program can decide from the characters of a text. The rules
are Agda under `--safe`, in [`agda/src/Prose/`](../../agda/src/Prose/), with proofs. Agda's GHC
backend compiles them into a program that reads the files of the repository.

```sh
tools/prose-check/run.sh ste FILE...                       # the STE rules, one line for each rule
tools/prose-check/run.sh ste --dictionary WORDS FILE...    # also rule 1.1, with a word list that you supply
tools/prose-check/run.sh ste --review FILE...              # the sentences to read for rules 3.5 and 3.6
tools/prose-check/run.sh ptc FILE...                       # PTC-5, PTC-7 and the paragraph limit
tools/prose-check/run.sh compare ORIGINAL EDITION          # the edition keeps the citations and numbers
tools/prose-check/run.sh self-test                         # the cases of Prose.Examples, compiled
bash checks/prose-check.sh                                 # all of it, as `just check` runs it (`just prose`)
```

`checks/prose-check.sh` applies the STE rules to each tracked Markdown file that has the line
"Writing standard: ASD-STE100". Today these files are `contextual-bandits/README.md` and this
file. It applies the PTC rules to the video script, `contextual-bandits/script/prose-pt-BR/`.

## How Agda can read a file

Under `--safe`, Agda cannot read a file or do other input and output. The standard library's
`IO` is not `--safe`, and a `--safe` module cannot have a `COMPILE` pragma. Thus the tool has two
parts:

- `agda/src/Prose/*.agda`, under `--safe --without-K`. These modules hold all the logic: the
  Markdown reader, the tokens and sentences, each rule, the report lines and the exit code.
  `checks/agda.sh` type-checks them with every other proof. A rule is a function of type
  `Sentence → Bool` or `Token → Bool`, so the program and the proofs use the same function.
- [`Main.agda`](Main.agda), without `--safe`. It reads the arguments and the files, calls
  `Prose.Cli.execute`, prints the lines and exits with the code. It has no rule.
  `checks/prose-check.sh` refuses a postulate, a pragma or foreign code in it.

`run.sh` compiles `Main.agda` with `agda --compile` (the MAlonzo backend) into `build/Main`. It
builds again when an Agda source is newer than the binary. The Agda wrapper of `nix develop .#agda`
calls the GHC of the same locked nixpkgs (GHC 9.10.3 with Agda 2.8.0 and the standard library 2.3,
pinned in `nix/agda.nix`). Thus the tool needs no new shell and no new pin. A run on the bandit
note takes about 0.04 s. The first build takes about 90 s.

The type-checker and the compiled program both get the character classes (`isAlpha`, `isSpace`)
from GHC's `Data.Char`. `Prose.Examples` checks 28 cases by `refl` at type-check time.
`self-test` runs 16 of them through the compiled program, so a fault of the compiler shows as a
failed case.

## What is proved

| Statement | Module | What it says |
|---|---|---|
| `holds-sound`, `holds-complete`, `broken-sound`, `broken-complete` | `TextChecks.Verdict` | a rule is OK when no unit breaks it, and only then. The report lists each unit that breaks it, and no other unit |
| `exit-zero`, `zero-exit` | `TextChecks.Verdict` | the exit code is 0 when each required rule is OK, and only then |
| `required-ok` | `Prose.Report` | a required rule with the verdict OK has no unit that breaks it |
| `off-never-fails` | `Prose.Report` | a rule that is off (rule 1.1 without a word list) never fails the run |
| `same-sound`, `same-complete` | `Prose.Facts` | `compare` says OK when each citation key and each number has the same count in the two texts, and only then |
| `paren-is-one-word`, `ste-26-words`, `ptc-paragraph-of-the-note` and 25 more | `Prose.Examples` | each rule rejects a bad text and accepts a good text, by `refl` |

The proofs are about the decision on the tokens. The Markdown reader (`Prose.Text`) is a
specification by definition: no proof says that it reads Markdown as pandoc does.

## ASD-STE100, rule by rule

The rule numbers are those of Issue 9, as the term checker table of simplified-english.co.uk lists
them ([Term checker rules for ASD-STE100 issue 9](https://simplified-english.co.uk/rules-ste9.html),
read 2026-11-11). The limits of 20 and 25 words and of 6 sentences come from Wikipedia's summary
of the rules
([Simplified Technical English](https://en.wikipedia.org/wiki/Simplified_Technical_English), read
2026-11-11). This work did not read the specification itself ⚠. ASD owns the copyright of
ASD-STE100. The repository holds no part of its dictionary.

| Rule | What it asks | In Agda |
|---|---|---|
| 1.1 | only words of the dictionary, technical nouns and technical verbs | **with a word list**: `--dictionary WORDS` (one word on each line) makes it a required rule. Without a list, the rule is OFF. Each part of a hyphenated word and the word without its `'s` must be in the list |
| 1.2 to 1.13 | the approved part of speech, meaning and form; technical nouns and verbs | a reader: the meaning of a word is not in its characters |
| 1.14 | American spelling | a word list again: give one with `--dictionary` |
| 2.1, 2.2 | at most three nouns in a noun cluster | a reader, or a part-of-speech tagger with a dictionary |
| 3.1 to 3.4, 3.7 | approved verb forms and tenses | a reader |
| 3.5 | the -ing form only in a technical noun | **review**: `--review` lists each word in -ing. Only a reader knows if it is a technical noun |
| 3.6 | active voice | **review**: `--review` lists a form of "be" before a word in -ed or a usual irregular participle |
| 4.1, 4.3, 4.4 | short and clear sentences, vertical lists, connecting words | a reader |
| 4.2 | no omitted words and no contractions | **decided, for contractions** (`STE-4.2`, required): a word that ends with n't, 're, 'll, 've, 'm or 'd, or a pronoun with 's. Omitted words need a reader |
| 4.5 | an article before a noun | a reader |
| 5.1 | short sentences in procedures, at most 20 words | **decided, recommended** (`STE-5.1`, a NOTE): a step of a numbered list. Only a reader knows if an item is an instruction |
| 5.2 to 5.5 | one instruction for each sentence, the imperative, notes | a reader |
| section 6 | descriptive writing: at most 25 words in a sentence, at most 6 sentences in a paragraph | **decided** (`STE-6`, two required rules) |
| 7.1 to 7.3 | safety instructions | a reader. The repository has no safety instructions |
| 8.1 | no semicolon | **decided** (`STE-8.1`, required) |
| 8.2 | hyphens | a reader |
| 8.5, 8.7 | text in parentheses counts as one word, and a hyphenated word counts as one word | **decided**, in the word count of `STE-6` and `STE-5.1` |
| 8.3, 8.4, 8.6 | parentheses, colons and the word count of lists | a reader |
| 9.1 to 9.4, GR-1 to GR-8 | the use of words, false friends, Latin abbreviations, pronouns | a reader |

Some decisions of this tool are not in the rules. A quotation in quotation marks counts as one
word, as text in parentheses does, because it holds the words of another writer. An inline code
span counts as one word. A reference marker (`[3]`, `[@key]`) is not a word. A fenced code block,
a heading, a table row, an HTML line, a block quote and an image are not prose.

## PTC, rule by rule

The video script follows PTC 1.2.0 at level `leve` (`00-como-ler.md`). The Haskell tool
[`tools/text-checks/`](../text-checks/README.md) applies all the PTC rules with regular
expressions. This tool states the rules below in Agda.

| Rule | In Agda | In Haskell |
|---|---|---|
| PTC-5, at most 35 words in a sentence | **decided** (required) | yes |
| PTC-7, the decimal point | **decided** (required) | yes |
| PTC-7, English thousands (`1,000,000`) and `DD/MM/YYYY` | **decided** (required) | yes |
| PTC-7, hours, unit symbols, ranges | possible in the same way, not written | yes |
| PTC-8, PTC-9, PTC-1, PTC-6 | possible: each one is a catalogue of patterns on the tokens of a sentence | yes |
| at most 6 sentences in a paragraph | **decided** (recommended, a NOTE) | yes |
| the meaning of a modal, the referent of a pronoun, the VOLP | a reader | `--review` lists the sentences |

A number with a point is not a decimal after the name of a thing with numbered parts. Examples
are a scene (`cena 1.2`), a section, a version, a model, and a paragraph of the note
(`parágrafo 1.7`). This is also true in a list (`cenas 1.2, 1.3 e 1.4`).

`parágrafo` was not in
the Haskell list, so `ptc` failed on `01-cmab.md:197` and `02-teste-ab.md:141`. This change adds
it to both tools. The Agda rule also finds a decimal before the point at the end of a sentence
(`custa 1.7.`). The Haskell pattern does not find it.

The two tools count the units in different ways. The Agda reader finds 509 sentences and 85
paragraphs in the script. The Haskell reader finds 508 sentences and 139 paragraphs, because it
also counts each heading and each table cell as a paragraph.

## The facts of an edition

The Gleam `ste-check` (removed on 2026-11-11) compared an STE edition `prose-ste/` with its
original. It failed when a citation or a number was lost or added. `compare` does the same for the
citation keys and the numbers, with `same-sound` and `same-complete` as its proofs. Today no paper
has a `prose-ste/` folder, so no check calls `compare`. The old check also compared the anchors,
the quotations and the `[ANALYSIS]` markers. These are not in `compare` yet.
