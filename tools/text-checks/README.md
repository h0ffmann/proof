# tools/text-checks: the text checks, in Haskell

Three checks that read text with regular expressions and ask Z3 whether a unit of it breaks a rule:
the language rule of `AGENTS.md`, the PTC rules of the video script and its PTC-9 noise catalogue.
They were Scala (`z3-scala/`, until 2026-11-11) and Python before that; this port keeps every
pattern and every rule, and prints the same lines, except that a hint names
`tools/text-checks/run.sh` where it named `z3-scala/z3.sh`.

```sh
tools/text-checks/run.sh language              # every tracked text file, one line per file that breaks the rule
tools/text-checks/run.sh ptc --self-test       # each required PTC check rejects a bad text and accepts a good one
tools/text-checks/run.sh ptc [--review]        # the PTC rules on contextual-bandits/script/prose-pt-BR/
tools/text-checks/run.sh ruido-ia --self-test  # each decided row of the catalogue rejects its bad text
tools/text-checks/run.sh ruido-ia [--review] [--level leve|descritivo|estrito]
bash checks/text-checks.sh                     # all five, as `just check` runs them
```

Each check measures every unit (a file, a sentence, a paragraph, a cell of the catalogue), gives
the measures to Z3 as constants through SBV (`Smt.hs`), and asks for a model of the negation of
the rule. `unsat` means that no unit breaks it; a model names the units that do. The decision layer
is proved for every measure in Agda, `agda/src/TextChecks/` (`--safe`, no postulate), which cannot
read a file: the measures are this tool's.

## Build

`run.sh` enters `nix develop .#text-checks` (`nix/text-checks.nix`) when the tools are not on
`PATH`, builds `Main.hs` with `ghc -O1 -Wall -Werror` into `tools/text-checks/build/`, and runs it
from the repository root. Every version comes from `flake.lock`'s nixpkgs:

| What | Version at the locked nixpkgs | Why |
|---|---|---|
| GHC, with `text`, `bytestring`, `containers`, `directory`, `process` | 9.10.3 and its bundled libraries | the language |
| `regex-pcre-builtin` | 0.95.2.3.8.44 (PCRE 8.44) | lookbehind, lookahead, Unicode classes and case folding, as Java's and Python's regular expressions have |
| `sbv` | 11.7 | the questions to Z3 |
| Z3 | 5.1.0 | the solver SBV runs |

## Text as Python read it (`Py.hs`)

The patterns were written for Python's `re` on `str`, where `\w`, `\d`, `\s` and `\b` are Unicode.
PCRE gets the same with UTF-8 mode and `PCRE_UCP`. Files are read as Python's text mode reads
them (UTF-8, universal newlines; a file that is not UTF-8 is not judged), and `strip`, `split` and
`splitlines` follow Python's Unicode whitespace. Offsets are bytes of the UTF-8 text, except the
20-character window of `CLITIC_OK`, which counts characters.

## The language rule (`Language.hs`)

`portuguese(f) <-> marked_pt_br(f)` for every tracked text file f: a file is Portuguese when its
Portuguese stop words are more than twice its English ones, fenced and inline code left out, and a
file with fewer than 20 stop words is not judged. `marked_pt_br(f)` is `pt-BR` in the path.
Binaries, generated formats and `vendor/` are skipped.

## The PTC rules of the video script (`Ptc.hs`)

The script's prose (`contextual-bandits/script/prose-pt-BR/`) follows Português Técnico Controlado
(PTC 1.2.0), level `leve`, for a human reader (`00-como-ler.md`, lines 3 to 6). Code, file names,
URLs, citation keys, quotations and italic foreign words are the protected zone of PTC (its
SKILL.md, "Processo", step 3) and are taken out first; a sentence keeps all its words for the
length check.

| Rule (level `leve`) | Required? | What Z3 checks | In `Ptc.hs` |
|---|---|---|---|
| PTC-5, sentence length | yes | every sentence has at most 35 words | `maxWords`, `words'` |
| PTC-7, number, date, unit | yes | no decimal point (a scene, a paragraph, a version, an ISO month are not decimals), no `1,000,000`, no `DD/MM/YYYY`, no AM/PM, a space before a unit symbol, no symbol in the plural, no `10-20` range | `numberFormat`, `decimalPoint`, `numberId` |
| PTC-8, spelling of 1990 | yes | the prefix and hyphen cases, the trema (not in a name), the open diphthong of a paroxytone, the abolished differential accents | `spelling`, `prefixHyphenVowel`, `trema` |
| PTC-9, chatbot noise | yes | no chatbot artefact, meta-text, model limit or generic conclusion | `noiseAlways` |
| PTC-1, coreference (the pattern part) | yes | no mesoclisis, no 3rd-person enclitic, no `o mesmo` as a pronoun | `clitic`, `cliticOk` |
| PTC-6, frozen names | yes (product and process names only) | one spelling for each name, no `API's`, the Brazilian variant | `frozen`, `frozenHits` |
| PTC-9, filler and inflation | recommended | no filler, vague attribution, copula evasion, inflation or made contrast | `noiseFiller` (a `NOTE`) |
| sentences per paragraph | recommended | at most 6 | `maxSentences` (a `NOTE`) |

What Z3 cannot decide (a parse, the referent of a pronoun, the VOLP, the meaning of a modal) is
the `reviewRules` list; `--review` prints the sentences a person must read for each one.

## The PTC-9 noise catalogue (`NoiseCatalogue.hs`)

The catalogue of PTC-9, `references/ruido-ia.md` of PTC 1.2.0, row by row (`catalogue`), on the
same sentences as `Ptc.hs`. A decided row gives every sentence a constant, its number of hits, and
Z3 is asked for a model of "some hit". The forms that the catalogue's "O que fica" keeps
(`estimador robusto`, `teorema fundamental`, `estado fundamental`, `proxy transparente`, and
`Contamos com vocês` at `leve`) are not hits, and a vague attribution with a citation key or a URL
in its sentence is not a hit. A row whose qualifier is meaning ("no sentido de ter", "como
ênfase") is read by a person: `--review` lists its sentences.
