"""The PTC rules of the video script, checked with Z3.

The video script (papers/contextual-bandits/script/prose-pt-BR/) is written in Portuguese
Técnico Controlado (PTC, kayquer/portugues-tecnico-controlado, version 1.2.0), level `leve`, for
a human reader (00-como-ler.md, lines 3 to 6). PTC has nine rules. At level `leve` some parts of
them are required, some are recommended, and some are off (the level table of the PTC SKILL.md).

This script takes the part of each rule that a program can measure on the text: a sentence
length, a spelling, a number format, a phrase. For every sentence (or paragraph) of the script it
measures that value, gives it to Z3 as a constant, states the rule as a formula over all the
sentences, and asks Z3 for a model of the negation. "unsat" means that no sentence breaks the
rule. "sat" gives the sentences that do, from the model.

    python3 z3/ptc.py            # one line per check; exit code 1 if a required check fails
    python3 z3/ptc.py --self-test   # each required check rejects a bad text, accepts a good one
    python3 z3/ptc.py --review   # also list the sentences a person must read, for each rule
                                 # (or part of a rule) that Z3 cannot decide

The text that PTC protects is taken out before the checks (SKILL.md, "Processo", step 3): code
(inline and fenced), file names, URLs, citation keys, and text in quotation marks (a quotation,
or a label on the screen). A sentence keeps all its words for the length check.

What Z3 cannot decide, and why, is in z3/README.md, "PTC rules that Z3 cannot prove".
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from z3 import BoolVal, Int, IntVal, Or, Solver, sat

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "papers/contextual-bandits/script/prose-pt-BR"
LEVEL = "leve"           # 00-como-ler.md, line 4
MAX_WORDS = 35           # PTC-5 at level leve, and 00-como-ler.md, line 6
MAX_SENTENCES = 6        # sentences per paragraph (recommended at level leve)


# ---------------------------------------------------------------------------------------------
# Reading the script: paragraphs, sentences, and the protected zone


@dataclass
class Unit:
    """A sentence (or a paragraph), with its place in the script."""
    file: str
    line: int
    text: str      # the words as written, code and quotations masked as one word each
    prose: str     # the same, with the quotations taken out too (what the rules apply to)
    raw: str = ""  # the sentence as written, for the report


FENCE = re.compile(r"^(```|~~~)")
DIV = re.compile(r"^:::")
HEADING_ATTR = re.compile(r"\{[.#][^}]*\}")
INLINE_CODE = re.compile(r"`[^`\n]*`")
URL = re.compile(r"<?https?://\S+?>?(?=[\s)\]]|$)")
CITATION = re.compile(r"\[@[^\]]*\]|@[A-Za-z][\w:-]*")
QUOTE = re.compile(r"\"[^\"\n]*\"|“[^”\n]*”")
EMPHASIS = re.compile(r"\*\*([^*\n]+?)\*\*")
ITALIC = re.compile(r"(?<![*\w])\*([^*\n]+?)\*(?![*\w])")    # a foreign word or a title
LABEL = re.compile(r"^\*\*[^*]+\.\*\*\s*")          # **Fala.**, **Tela.**, **Código.**
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+\.)\s+")
TABLE_RULE = re.compile(r"^\|?[\s:|-]+\|?$")
CAPTION = re.compile(r"^:\s+")
# A sentence ends at . ! ? or … (and a closing quotation mark, bracket or code mark) before a
# space and a capital letter, a digit, a quotation mark, a bracket, a code mark or an emphasis. Abbreviations that end with a point are not ends.
SENTENCE_END = re.compile(r"(?:(?<=[.!?…])|(?<=[.!?…][`\"”)\]])|(?<=[.!?…]\][`]))\s+"
                          r"(?=[\"“(\[*`⚠A-ZÁÉÍÓÚÂÊÔÃÕÇπ0-9])")
# An inline list: "1952 Robbins · 2010 LinUCB · ...". Each item is a unit, as in a list.
INLINE_LIST = re.compile(r"\s+·\s+")
ABBREVIATION = re.compile(r"\b(?:p|ex|Sr|Sra|Dr|Dra|etc|vs|cf|N|nº)\.$", re.IGNORECASE)
WORD = re.compile(r"[^\s|·—–⚠*]+")


def mask(text: str) -> str:
    """Protected zone (code, URL, citation) becomes one word: X."""
    text = INLINE_CODE.sub(" X ", text)
    text = URL.sub(" X ", text)
    text = CITATION.sub(" ", text)          # a citation is not a word of the sentence
    return text


def front_matter(lines: list[str]) -> tuple[list[tuple[int, str]], int]:
    """The prose of a YAML front matter: title, subtitle and abstract. Returns (lines, end)."""
    if not lines or lines[0].strip() != "---":
        return [], 0
    out: list[tuple[int, str]] = []
    key = None
    for n, line in enumerate(lines[1:], start=2):
        if line.strip() == "---":
            return out, n
        m = re.match(r"^(\w[\w-]*):\s*(.*)$", line)
        if m:
            key, value = m.group(1), m.group(2).strip()
            if key in ("title", "subtitle") and value:
                out.append((n, value.strip("\"'") + "."))
                out.append((n, ""))
            elif key == "abstract":
                pass
            continue
        if key == "abstract":
            out.append((n, line.strip()))
    return out, len(lines)


def paragraphs(path: Path) -> list[list[tuple[int, str]]]:
    """Blocks of prose lines, with line numbers. A list item and a table cell are blocks."""
    lines = path.read_text(encoding="utf-8").splitlines()
    head, start = front_matter(lines)
    numbered = head + [(n, line) for n, line in enumerate(lines[start:], start=start + 1)]
    blocks: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    in_code = False

    def flush() -> None:
        nonlocal current
        if current:
            blocks.append(current)
        current = []

    for n, line in numbered:
        if FENCE.match(line.strip()):
            in_code = not in_code
            flush()
            continue
        if in_code or DIV.match(line.strip()):
            continue
        stripped = line.strip()
        if not stripped:
            flush()
            continue
        if stripped.startswith("#"):
            flush()
            title = HEADING_ATTR.sub("", stripped.lstrip("#")).strip()
            if title:
                blocks.append([(n, title)])
            continue
        if stripped.startswith("|"):
            flush()
            if not TABLE_RULE.match(stripped):
                for cell in stripped.strip("|").split("|"):
                    if cell.strip():
                        blocks.append([(n, cell.strip())])
            continue
        if LIST_ITEM.match(line):
            flush()
            current = [(n, LIST_ITEM.sub("", line))]
            continue
        if CAPTION.match(stripped):
            flush()
            current = [(n, CAPTION.sub("", stripped))]
            continue
        current.append((n, stripped))
    flush()
    return blocks


def split_sentences(block: list[tuple[int, str]], file: str) -> tuple[list[Unit], int]:
    """The sentences of one block, each with the line where it starts, and the number of
    sentences (an inline list gives one unit per item, but it is one sentence)."""
    text, starts = "", []
    for n, line in block:
        starts.append((len(text), n))
        text += line + " "
    first = LABEL.match(text)
    offset = first.end() if first else 0
    units: list[Unit] = []
    count = 0
    piece_start = offset
    for m in list(SENTENCE_END.finditer(text, offset)) + [None]:
        end = m.start() if m else len(text)
        piece = text[piece_start:end].strip()
        if m and ABBREVIATION.search(piece):
            continue
        line = max(n for pos, n in starts if pos <= piece_start) if piece else 0
        count += bool(piece)
        for item in INLINE_LIST.split(piece) if piece else []:
            masked = mask(EMPHASIS.sub(r"\1", item))
            prose = ITALIC.sub(" Q ", QUOTE.sub(" Q ", masked))
            units.append(Unit(file, line, ITALIC.sub(r"\1", masked), prose, item))
        if m:
            piece_start = m.end()
    return units, count


def read_script() -> tuple[list[Unit], list[Unit]]:
    """(sentences, paragraphs) of every Markdown file of the script."""
    sentences: list[Unit] = []
    paras: list[Unit] = []
    for path in sorted(SCRIPT.glob("*.md")):
        name = str(path.relative_to(ROOT))
        for block in paragraphs(path):
            units, count = split_sentences(block, name)
            sentences += units
            if units:
                paras.append(Unit(name, units[0].line, " ".join(u.text for u in units),
                                  str(count)))
    return sentences, paras


def words(unit: Unit) -> int:
    return len([w for w in WORD.findall(unit.text) if re.search(r"\w", w)])


# ---------------------------------------------------------------------------------------------
# The rules, as patterns over the prose (the protected zone is already out)


def any_of(*patterns: str, flags: int = re.IGNORECASE) -> re.Pattern[str]:
    return re.compile("|".join(f"(?:{p})" for p in patterns), flags)


VOWEL = "aeiouáéíóúâêôãõ"
# PTC-8: prefixes that end in a vowel (SKILL.md, PTC-8; references/ortografia-ptbr.md)
PREFIX_V = r"(?:micro|auto|anti|contra|semi|mini|ultra|infra|extra|multi|intra|neo|pseudo|proto|retro|macro|mega|poli|tele|hidro|termo|eletro|foto|geo|bio|socio)"
SPELLING = any_of(
    r"\b(?:idéia|assembléia|heróico|jibóia|geléia|européia|européias|platéia|estréia|"
    r"apóia|bóia|paranóia|epopéia|colméia|alcatéia|asteróide|onomatopéia|"
    r"jóia|jóias|idéias|heróicos|heróica)\b",                   # open diphthong in a paroxytone
    r"\b(?:vôo|vôos|enjôo|enjôos|lêem|crêem|vêem|dêem|relêem|prevêem|abençôo|perdôo)\b",
    r"\b(?:pára|pêlo|pêlos|pólo|pólos|pêra)\b",                   # abolished differential accents
    r"\b(?:co|re)-\w+",                                           # co-autor, re-escrever
    r"\bré-\w+",
    r"\b(?:pre|pos|pro)-(?=\w)",                                  # pré-, pós-, pró- keep the accent
    r"\bnão-\w+",                                                 # não-conformidade
    r"\bsubr\w+",                                                 # subrotina -> sub-rotina
    r"\binterrela\w*",                                            # interrelação -> inter-relação
    r"\bsuper-(?![hr])\w+",                                       # super-usuário -> superusuário
    r"\binter-(?!r)\w+",                                          # inter-operabilidade
    r"\b" + PREFIX_V + r"-[rs]\w+",                               # micro-serviço -> microsserviço
    r"\b" + PREFIX_V + r"[rs][" + VOWEL + r"]\w*",                 # microserviço -> microsserviço
)
# prefix (ends in a vowel) + hyphen + a vowel: a hyphen only when the two vowels are the same
PREFIX_HYPHEN_VOWEL = re.compile(r"\b(" + PREFIX_V + r")-([" + VOWEL + r"])\w*", re.IGNORECASE)
TREMA = re.compile(r"\b[a-zà-ú]\w*ü\w*")                       # trema, but not in a name (Müller)
# Words that the last pattern would take and that are right.
SPELLING_OK = re.compile(
    r"^(?:autor\w*|automático\w*|micros?|microsoft|auto(?:s|res)?|antes|contrast\w*|termos?"
    r"|bios|neos|geos|fotos|polos?|telas?|telescópio\w*|proto|retros?|semis?|minis?|macros?"
    r"|megas?|ultras?|infras?|extras?|multis?|intras?|socios?|eletros?|hidros?)$", re.IGNORECASE)

# PTC-7: number, date, hour, unit, range
DECIMAL_POINT = re.compile(r"(?<![\w.,/:-])\d+\.\d{1,2}(?![\d.,])|(?<![\w.,/:-])\d+\.\d{4,}(?![\d.,])")
# A number with a point that is not a decimal: a scene, a version, a model, an IP-like id.
NUMBER_ID = re.compile(
    r"(?:\b(?:cenas?|scene|takes?|seção|versão|v|V|Sonnet|Fable|Opus|Haiku|Claude|Lean|Z3|GHC"
    r"|OpenVoice|XTTS|Python|pandoc)\s*(?:\d+(?:\.\d+)*\s*(?:,|e|a)\s*)*$)", re.IGNORECASE)
NUMBER_FORMAT = any_of(
    r"\b\d{1,3}(?:,\d{3}){2,}\b",                                 # 1,000,000 (English thousands)
    r"\b\d{1,2}/\d{1,2}/\d{2,4}\b",                               # 02/08/2026
    r"\b\d{1,2}(?::\d{2})?\s?(?:AM|PM|a\.m\.|p\.m\.)(?!\w)",       # 2:30 PM
    r"\b\d+(?:[.,]\d+)?(?:ms|min|GB|MB|KB|TB|kB|kg|km|cm|mm|GHz|MHz|Hz|kW|W|°C|%)(?!\w)",
    r"\b\d+(?:[.,]\d+)?\s(?:kgs|kms|mins|GBs|MBs)\b",             # pluralized symbol
    r"(?<![\w-])\d+-\d+(?![\w-])(?<!\b\d{4}-\d{2})",              # 10-20 as a range (not 2017-12)
    flags=0)

# PTC-9, the part that leaves in every level: chatbot artefact, meta-text, model limit, generic end
NOISE_ALWAYS = any_of(
    r"\bclaro!", r"\bcom certeza!", r"\bperfeito!", r"\b(?:ótima|boa|excelente) pergunta\b",
    r"\bexcelente observação\b", r"\bespero (?:ter ajudado|que (?:isso )?(?:ajude|tenha ajudado))\b",
    r"\bfique à vontade para\b", r"\bqualquer dúvida, estou à disposição\b",
    r"\bvamos (?:lá|explorar|entender|mergulhar)\b", r"\bneste documento, vamos\b",
    r"\ba seguir, veremos\b", r"\bem resumo, vimos\b",
    r"\bcom base nas informações disponíveis\b", r"\baté onde (?:sei|eu sei)\b",
    r"\bo futuro é promissor\b", r"\bsó o tempo dirá\b", r"\buma coisa é certa\b",
    r"\bvou analisar passo a passo\b", r"\bpensando nisso de forma estruturada\b",
    r"\bcomo (?:um )?(?:modelo de linguagem|uma IA|IA)\b")

# PTC-9, the part that is recommended at level leve: filler, confidence, vague attribution,
# copula evasion, inflation
NOISE_FILLER = any_of(
    r"\balém disso\b", r"\bademais\b", r"\boutrossim\b", r"\bnesse sentido\b",
    r"\bquando se trata de\b", r"\bno cenário atual\b", r"\bnos dias de hoje\b",
    r"\bem um mundo cada vez mais\b", r"\bem (?:suma|síntese|conclusão)\b",
    r"\b(?:vale|cabe) (?:destacar|ressaltar|lembrar|mencionar)\b", r"\bé importante mencionar\b",
    r"\b(?:notavelmente|curiosamente|surpreendentemente|indiscutivelmente)\b",
    r"\bsem dúvida\b", r"\bde fato\b", r"\bcertamente\b",
    r"\b(?:estudos|especialistas|pesquisas) (?:mostram|apontam|indicam)\b",
    r"\bé (?:sabido|consenso) que\b",
    r"\b(?:atua|se configura|se destaca) (?:como|por)\b", r"\bdispõe de\b",
    r"\b(?:robust[oa]s?|de ponta|de última geração|sem atrito|alavancar\w*|alavancad[oa]s?|"
    r"alavancando|potencializ\w+|"
    r"impulsion\w+|divisor de águas|revolucionári[oa]s?|transformador[ae]?s?|primordial)\b",
    r"\bnão é só\b.{0,60}\bé\b")

# PTC-1, the parts a pattern finds: mesoclisis, 3rd-person enclitic, "o mesmo" as a pronoun
CLITIC = re.compile(
    r"\b\w+-(?:se|lo|la|los|las|me|te|nos|vos|lhe|lhes|o|a|os|as)-(?:á|ão|ás|ia|iam|ei|emos|íamos)\b"
    r"|\b\w+[áéêíô]?-(?:o|a|os|as|lo|la|los|las|lhe|lhes)\b(?!-)"
    r"|\b(?:o|a|os|as|do|da|dos|das|no|na|nos|nas|ao|à|aos|às|pelo|pela|pelos|pelas)\s+mesm[oa]s?"
    r"(?=\s*[.,;:!?)]|\s+(?:foi|foram|é|são|está|estão|será|serão|tem|têm|deve|devem|pode|podem)\b)",
    re.IGNORECASE)
# "a mesma" after "é" or "sempre" is an adjective (the question is the same), not a pronoun.
CLITIC_OK = re.compile(r"\b(?:é|são|era|eram|foi|fica|ficam|sempre|continua|continuam)\s+(?:sempre\s+)?"
                       r"(?:o|a|os|as)\s+mesm[oa]s?\b", re.IGNORECASE)

# PTC-6 at level leve: product and process names are frozen. One spelling for each.
FROZEN = ["3Blue1Brown", "Manim", "Desmos", "OpenVoice", "MeloTTS", "XTTS", "Piper", "Coqui",
          "MyShell", "Lean", "Haskell", "Z3", "Netflix", "LinUCB", "CMAB", "RSI", "Claude Code",
          "Anthropic", "globo.com", "Scala", "Python", "GitHub", "Thompson", "A/B"]
APOSTROPHE_PLURAL = re.compile(r"\b[A-Z]{2,}'s\b")
BR_VARIANT = re.compile(r"\b(?:ficheiros?|utilizador(?:es)?|ecrãs?|equipas?|registos?)\b", re.I)


def frozen_hits(prose: str) -> list[str]:
    hits = []
    for name in FROZEN:
        for m in re.finditer(r"(?<![\w/])" + re.escape(name) + r"(?![\w/])", prose, re.IGNORECASE):
            if m.group(0) != name and not (name == "Lean" and m.group(0) == "lean"):
                hits.append(m.group(0))
    hits += APOSTROPHE_PLURAL.findall(prose) + BR_VARIANT.findall(prose)
    return hits


def spelling_hits(prose: str) -> list[str]:
    hits = [m.group(0) for m in SPELLING.finditer(prose) if not SPELLING_OK.match(m.group(0))]
    hits += [m.group(0) for m in PREFIX_HYPHEN_VOWEL.finditer(prose)
             if m.group(1)[-1].lower() != m.group(2).lower()]
    return hits + TREMA.findall(prose)


def number_hits(prose: str) -> list[str]:
    hits = [m.group(0) for m in NUMBER_FORMAT.finditer(prose)]
    for m in DECIMAL_POINT.finditer(prose):
        if not NUMBER_ID.search(prose[:m.start()]):
            hits.append(m.group(0))
    return hits


def clitic_hits(prose: str) -> list[str]:
    ok = {m.start() for m in CLITIC_OK.finditer(prose)}
    hits = []
    for m in CLITIC.finditer(prose):
        if any(start <= m.start() <= start + 20 for start in ok):
            continue
        hits.append(m.group(0))
    return hits


def pattern(regex: re.Pattern[str]) -> Callable[[str], list[str]]:
    return lambda prose: [m.group(0) for m in regex.finditer(prose)]


# ---------------------------------------------------------------------------------------------
# The checks Z3 decides


@dataclass
class Check:
    rule: str
    name: str
    required: bool                       # required at level leve; else recommended
    over: str                            # "sentence" or "paragraph"
    measure: Callable[[Unit], int]       # the value Z3 gets for one unit
    limit: int                           # the rule: measure(unit) <= limit, for every unit
    explain: Callable[[Unit], str]


def hits_check(rule: str, name: str, required: bool, find: Callable[[str], list[str]]) -> Check:
    return Check(rule, name, required, "sentence", lambda u: len(find(u.prose)), 0,
                 lambda u: ", ".join(dict.fromkeys(find(u.prose))))


CHECKS = [
    Check("PTC-5", f"every sentence has at most {MAX_WORDS} words", True, "sentence",
          words, MAX_WORDS, lambda u: f"{words(u)} words"),
    hits_check("PTC-7", "numbers, dates, hours, units and ranges in the Brazilian format", True,
               number_hits),
    hits_check("PTC-8", "spelling of the 1990 Agreement (hyphen, accent, trema)", True,
               spelling_hits),
    hits_check("PTC-9", "no chatbot artefact, meta-text or generic conclusion", True,
               pattern(NOISE_ALWAYS)),
    hits_check("PTC-1", "no mesoclisis, 3rd-person enclitic, or 'o mesmo' as a pronoun", True,
               clitic_hits),
    hits_check("PTC-6", "product and process names in one spelling; Brazilian variant", True,
               frozen_hits),
    hits_check("PTC-9", "no filler, vague attribution or inflation (recommended)", False,
               pattern(NOISE_FILLER)),
    Check("PTC", f"at most {MAX_SENTENCES} sentences in a paragraph (recommended)", False,
          "paragraph", lambda u: int(u.prose), MAX_SENTENCES, lambda u: f"{u.prose} sentences"),
]


def prove(check: Check, units: list[Unit]) -> tuple[bool, list[Unit]]:
    """Ask Z3 for a unit with measure > limit. Returns (holds, the units of the model)."""
    solver = Solver()
    limit = Int("limit")
    solver.add(limit == IntVal(check.limit))
    broken = []
    for i, unit in enumerate(units):
        x = Int(f"{check.rule}[{i}]")
        solver.add(x == IntVal(check.measure(unit)))
        broken.append(x > limit)
    solver.add(Or(*broken) if broken else BoolVal(False))
    if solver.check() != sat:
        return True, []
    model = solver.model()
    return False, [u for u, b in zip(units, broken) if model.eval(b)]


# ---------------------------------------------------------------------------------------------
# What Z3 cannot decide: the sentences a person reads, for each rule


REVIEW: list[tuple[str, str, re.Pattern[str] | None]] = [
    ("PTC-1", "every finite clause has a lexical subject; no pronoun or demonstrative points "
     "outside its sentence; no actor is invented (required). Needs a parse and the reference of "
     "each pronoun. Read the sentences that open with a pronoun or a demonstrative.",
     re.compile(r"^(?:\W*)(?:Ele|Ela|Eles|Elas|Esse|Essa|Esses|Essas|Isso|Este|Esta|Isto|Aquele"
                r"|Aquela|Aquilo|Nesse|Nessa|Neste|Nesta|Disso|Desse|Dessa)\b")),
    ("PTC-1", "no proclitic 3rd-person pronoun ('o calcula', 'a mostra'): 'o' and 'a' are also "
     "articles, so only a parse tells them apart. Read the sentences with 'o'/'a' before a verb "
     "form in -a, -e or -am after a noun or 'que'.",
     re.compile(r"\b(?:que|não|já|se|nunca|também)\s+(?:o|a|os|as|lhe|lhes)\s+\w+(?:a|e|am|em)\b",
                re.IGNORECASE)),
    ("Level table", "a condition or a safety note opens the sentence (required). Needs the scope "
     "of 'se', 'quando', 'caso', which a pattern cannot fix. Read the sentences where one of them "
     "is not the first word.",
     re.compile(r"(?<!^)(?<!\W\s)(?:,\s*(?:se|quando|caso)\s|\s(?:exceto|a menos que|desde que)\s)",
                re.IGNORECASE)),
    ("PTC-2", "no gerund that joins two clauses (recommended). A gerund after 'estar' is fine; "
     "only the meaning tells the two apart. Read the sentences with a gerund after a comma.",
     re.compile(r",\s+\w+ndo\b", re.IGNORECASE)),
    ("PTC-3", "one meaning per modal; no hedge (recommended, a social hedge is fine). 'deve' is "
     "obligation or probability, 'pode' is permission or capacity: only the meaning decides. "
     "Read the sentences with a modal.",
     re.compile(r"\b(?:dev[eo]\w*|deveria\w*|pode\w*|poderia\w*|talvez)\b", re.IGNORECASE)),
    ("PTC-5", "an adjective goes after its noun (recommended). Needs a part-of-speech tag. Read "
     "the sentences where an adjective whose meaning changes with its place comes first.",
     re.compile(r"\b(?:um|uma|o|a|os|as|cada|todo|toda)\s+(?:simples|cert[oa]s?|únic[oa]s?|nov[oa]s?"
                r"|velh[oa]s?|grandes?|pobres?|antig[oa]s?|bel[oa]s?|pur[oa]s?|mer[oa]s?)\s+[a-zçãõé]+",
                re.IGNORECASE)),
    ("PTC-6", "one concept, one term, in the whole script (required for product and process "
     "names, checked above; the rest is off at level leve). A synonym for the same concept is "
     "a matter of meaning: no list can hold all of them.", None),
    ("PTC-8", "spelling outside the curated list (required). The check covers the four hyphen "
     "cases, the trema, the open diphthong and the differential accents of the PTC reference; "
     "any other word needs the VOLP of the Academia Brasileira de Letras, which has no API.",
     None),
    ("PTC-9", "a sentence that says nothing (required for chatbot artefacts, checked above). "
     "The PTC test is 'what is lost if it goes?', which is a question of meaning.", None),
]


def review(sentences: list[Unit]) -> None:
    print("\nRules (or parts of rules) that Z3 cannot decide: read these sentences.")
    for rule, why, candidates in REVIEW:
        print(f"\n{rule}: {why}")
        if candidates is None:
            continue
        found = [u for u in sentences if candidates.search(u.prose)]
        for u in found:
            snippet = u.raw if len(u.raw) <= 100 else u.raw[:97] + "..."
            print(f"  {u.file}:{u.line}  {snippet}")
        print(f"  ({len(found)} sentences)")


# Each required check must reject its BAD text and accept its GOOD text (python3 z3/ptc.py
# --self-test). GOOD holds the right forms that look like a break: a scene number, a model
# version, an ISO month, a hyphen that stays, a name with a trema, "a mesma" as an adjective.
SELF_TEST = {
    "PTC-5": ("Esta frase tem " + "muitas " * 33 + "palavras.",
              "Esta frase tem " + "poucas " * 30 + "palavras."),
    "PTC-7": ("O arquivo tem 1.5 GB, a fila leva 200ms, de 10-20 itens, em 02/08/2026 às 2:30 PM.",
              "A cena 1.4 usa o Claude Sonnet 5.5, 100.000 termos, 0,67, 67 %, 14h30, em 2017-12."),
    "PTC-8": ("A infra-estrutura usa micro-serviços, um co-autor e a idéia é freqüente.",
              "O anti-inflamatório, o pré-requisito, a infraestrutura, os microsserviços e Müller."),
    "PTC-9": ("Ótima pergunta! O futuro é promissor. Espero ter ajudado!",
              "O serviço reinicia em 5 s."),
    "PTC-1": ("O pedido chegou. O mesmo foi cancelado. Far-se-á o backup. O laço aprende a enganá-la.",
              "A pergunta é sempre a mesma: a crença nova escolhe a mesma coisa?"),
    "PTC-6": ("O manim desenha as API's no ecrã.",
              "O Manim desenha as APIs na tela."),
}


def self_test() -> int:
    bad = 0
    for check in CHECKS:
        if not check.required:
            continue
        reject, accept = SELF_TEST[check.rule]
        for text, should_hold in ((reject, False), (accept, True)):
            units, _ = split_sentences([(1, text)], "self-test")
            holds, _ = prove(check, units)
            if holds != should_hold:
                bad += 1
                print(f"FAIL  self-test {check.rule}: {'accepts' if holds else 'rejects'} {text!r}")
    print("OK    self-test: every required check rejects its bad text and accepts its good text"
          if not bad else f"\n{bad} self-test failure(s)")
    return 1 if bad else 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    sentences, paras = read_script()
    failed = 0
    print(f"PTC, level {LEVEL}: {len(sentences)} sentences and {len(paras)} paragraphs "
          f"in {SCRIPT.relative_to(ROOT)}/")
    for check in CHECKS:
        units = sentences if check.over == "sentence" else paras
        holds, broken = prove(check, units)
        status = "OK  " if holds else ("FAIL" if check.required else "NOTE")
        print(f"{status}  {check.rule}: {check.name} ({'unsat' if holds else 'sat'})")
        for u in broken:
            print(f"        {u.file}:{u.line}: {check.explain(u)}")
        if not holds and check.required:
            failed += 1
    if "--review" in sys.argv:
        review(sentences)
    if failed:
        print(f"\n{failed} required PTC check(s) fail")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
