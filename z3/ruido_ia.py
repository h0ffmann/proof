"""The PTC-9 noise catalogue (references/ruido-ia.md), checked on the video script with Z3.

PTC-9 says: if a passage goes and no fact, condition or instruction is lost, it is noise. The PTC
repository (kayquer/portugues-tecnico-controlado, references/ruido-ia.md) lists where that noise
usually shows up in technical text written or revised by a model, in four tables:

    Sempre sai        out at every level, `leve` too            required at leve
    Enchimento        out at estrito and descritivo             recommended at leve
    Evasão de cópula  out at estrito and descritivo             off at leve
    Inflação          out at estrito and descritivo             off at leve

z3/ptc.py already checks a short form of PTC-9 (NOISE_ALWAYS, NOISE_FILLER). This script checks
the catalogue itself, entry by entry, so that a change to the catalogue is a change to one row
of CATALOGUE below. Each row is either:

- decided: the "Evite" phrase is a break wherever it stands, except in the forms that the
  catalogue's "O que fica" section keeps (KEEP). For every sentence s and every such row e, the
  number of hits is a Z3 constant h[e][s]. Z3 is asked for a model of "some h[e][s] > 0". unsat
  means that no sentence breaks the table.
- read: the row has a qualifier that needs the meaning of the sentence ("no sentido de ter",
  "sem relação causal", "como ênfase"). No formula over the text decides it, so --review lists
  the sentences that carry the phrase, for a person to read.

    python3 z3/ruido_ia.py                 # one line per table; exit 1 if a required table fails
    python3 z3/ruido_ia.py --self-test     # every decided row rejects its bad text, KEEP passes
    python3 z3/ruido_ia.py --review        # also the sentences a person must read, row by row
    python3 z3/ruido_ia.py --level estrito # the level (default: leve, 00-como-ler.md, line 4)

The protected zone (code, URLs, quotations, italic foreign words) is taken out first, as in
ptc.py, whose reader this script uses.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass

from z3 import BoolVal, Int, IntVal, Or, Solver, sat

from ptc import LEVEL, ROOT, SCRIPT, Unit, read_script, split_sentences

SOURCE = "kayquer/portugues-tecnico-controlado, references/ruido-ia.md (PTC 1.2.0)"

# Section -> {level: "required" | "recommended" | "off"} (the line under each table heading).
SECTIONS = {
    "Sempre sai": {"leve": "required", "descritivo": "required", "estrito": "required"},
    "Enchimento": {"leve": "recommended", "descritivo": "required", "estrito": "required"},
    "Evasão de cópula": {"leve": "off", "descritivo": "required", "estrito": "required"},
    "Inflação": {"leve": "off", "descritivo": "required", "estrito": "required"},
}


@dataclass
class Row:
    section: str
    avoid: str                 # the "Evite" cell, as in ruido-ia.md
    pattern: re.Pattern[str]
    decided: bool              # True: Z3 decides it; False: a person reads the candidates
    bad: str = ""              # self-test: a sentence the row must reject (decided rows)
    why: str = ""              # read rows: what Z3 would need to know


def p(*alternatives: str, start: bool = False) -> re.Pattern[str]:
    body = "|".join(f"(?:{a})" for a in alternatives)
    return re.compile((r"^\W*(?:" if start else r"(?:") + body + ")", re.IGNORECASE)


CATALOGUE = [
    # Sempre sai
    Row("Sempre sai", "Claro! / Com certeza! / Perfeito!",
        p(r"\bclaro\s*!", r"\bcom certeza\s*!", r"\bperfeito\s*!"), True,
        "Claro! O serviço reinicia em 5 s."),
    Row("Sempre sai", "Ótima pergunta / Excelente observação",
        p(r"\b(?:ótima|excelente|boa) pergunta\b", r"\b(?:ótima|excelente) observação\b"), True,
        "Ótima pergunta, o serviço reinicia em 5 s."),
    Row("Sempre sai", "Espero ter ajudado / Espero que isso ajude",
        p(r"\bespero (?:ter ajudado|que (?:isso )?(?:ajude|tenha ajudado))\b"), True,
        "O serviço reinicia em 5 s. Espero que isso ajude."),
    Row("Sempre sai", "Fique à vontade para / Qualquer dúvida, estou à disposição",
        p(r"\bfique à vontade para\b", r"\bqualquer dúvida,? estou à disposição\b",
          r"\bestou à disposição\b"), True,
        "Fique à vontade para abrir um chamado."),
    Row("Sempre sai", "Vamos lá / Vamos explorar / Vamos entender",
        p(r"\bvamos (?:lá|explorar|entender)\b"), True,
        "Vamos entender o cache."),
    Row("Sempre sai", "Vamos + another verb (the same false collaborative opening)",
        p(r"\bvamos (?!lá\b|explorar\b|entender\b)\w+"), False,
        why="the table names three verbs; with another verb, whether the opening delays the "
            "subject or is the subject is meaning, and 1st person is allowed at leve"),
    Row("Sempre sai", "Neste documento, vamos abordar… / A seguir, veremos…",
        p(r"\bneste (?:documento|texto|artigo|vídeo),? vamos\b", r"\ba seguir,? veremos\b"), True,
        "Neste documento, vamos abordar o cache."),
    Row("Sempre sai", "Em resumo, vimos que…",
        p(r"\bem resumo,? vimos\b"), True,
        "Em resumo, vimos que o cache expira."),
    Row("Sempre sai", "Com base nas informações disponíveis / Até onde sei",
        p(r"\bcom base nas informações disponíveis\b", r"\baté onde (?:eu )?sei\b"), True,
        "Até onde sei, o cache expira em 60 s."),
    Row("Sempre sai", "O futuro é promissor / Só o tempo dirá / Uma coisa é certa",
        p(r"\bo futuro é promissor\b", r"\bsó o tempo dirá\b", r"\buma coisa é certa\b"), True,
        "Só o tempo dirá."),
    Row("Sempre sai", "Vou analisar passo a passo / Pensando nisso de forma estruturada",
        p(r"\bvou analisar passo a passo\b", r"\bpensando nisso de forma estruturada\b"), True,
        "Vou analisar passo a passo o log."),

    # Enchimento
    Row("Enchimento", "além disso / ademais / outrossim (abrindo frase)",
        p(r"além disso\b", r"ademais\b", r"outrossim\b", start=True), True,
        "Além disso, o cache expira."),
    Row("Enchimento", "além disso / ademais / outrossim (no meio da frase)",
        p(r"\balém disso\b", r"\bademais\b", r"\boutrossim\b"), False,
        why="inside a sentence the connector may add a real second item; only the meaning tells"),
    Row("Enchimento", "nesse sentido / dessa forma / desse modo (sem relação causal)",
        p(r"\bnesse sentido\b", r"\bdess[ae] (?:forma|modo|maneira)\b"), False,
        why="'O que fica' keeps it when it marks a real consequence; causality is meaning"),
    Row("Enchimento", "quando se trata de X",
        p(r"\bquando se trata de\b"), True, "Quando se trata de cache, o TTL é 60 s."),
    Row("Enchimento", "no cenário atual / nos dias de hoje / em um mundo cada vez mais…",
        p(r"\bno cenário atual\b", r"\bnos dias de hoje\b", r"\bem um mundo cada vez mais\b"), True,
        "No cenário atual, o cache expira em 60 s."),
    Row("Enchimento", "em suma / em síntese / em conclusão",
        p(r"\bem (?:suma|síntese|conclusão)\b"), True, "Em suma, o cache expira em 60 s."),
    Row("Enchimento", "vale destacar / cabe ressaltar / é importante mencionar",
        p(r"\b(?:vale|cabe) (?:a pena )?(?:destacar|ressaltar|mencionar|lembrar|notar)\b",
          r"\bé importante (?:mencionar|destacar|ressaltar|notar|lembrar)\b"), True,
        "Vale destacar que o cache expira em 60 s."),
    Row("Enchimento", "notavelmente / curiosamente / surpreendentemente",
        p(r"\b(?:notavelmente|curiosamente|surpreendentemente)\b"), True,
        "Curiosamente, o cache expira em 60 s."),
    Row("Enchimento", "sem dúvida / certamente / de fato / indiscutivelmente",
        p(r"\bsem dúvida\b", r"\bcertamente\b", r"\bde fato\b", r"\bindiscutivelmente\b"), True,
        "O cache, sem dúvida, expira em 60 s."),
    Row("Enchimento", "estudos mostram / especialistas apontam / pesquisas indicam",
        p(r"\b(?:estudos|especialistas|pesquisas|pesquisadores)"
          r" (?:mostram|apontam|indicam|sugerem|dizem)\b"), True,
        "Estudos mostram que o cache ajuda."),
    Row("Enchimento", "é sabido que / é consenso que",
        p(r"\bé (?:sabido|consenso|notório) que\b"), True, "É sabido que o cache ajuda."),

    # Evasão de cópula
    Row("Evasão de cópula", "atua como / funciona como / se configura como",
        p(r"\b(?:atua|atuam|funciona|funcionam) como\b", r"\bse configura(?:m)? como\b"), True,
        "O Redis atua como cache."),
    Row("Evasão de cópula", "conta com / dispõe de / possui",
        p(r"\bconta(?:m)? com\b", r"\bdispõe(?:m)? de\b", r"\bposs(?:ui|uem|uir)\b"), True,
        "O cluster conta com 3 nós."),
    Row("Evasão de cópula", "apresenta (no sentido de ter)",
        p(r"\bapresenta(?:m)?\b"), False,
        why="'apresentar erro' and 'apresentar ao público' are other senses; the sense is meaning"),
    Row("Evasão de cópula", "representa (no sentido de ser)",
        p(r"\brepresenta(?:m)?\b"), False,
        why="'a seta representa o fluxo' (a symbol stands for a thing) is not a copula"),
    Row("Evasão de cópula", "se destaca por",
        p(r"\bse destaca(?:m)? (?:por|pel[oa]s?)\b"), True, "O Redis se destaca pela latência."),

    # Inflação
    Row("Inflação", "robusto (elogio vago)",
        p(r"\brobust[oa]s?\b"), False,
        why="'estimador robusto' is a term; a vague praise needs the absence of a criterion"),
    Row("Inflação", "abrangente / completo (sem dizer o que cobre)",
        p(r"\babrangentes?\b", r"\bcomplet[oa]s?\b"), False,
        why="the row is out only when the text does not say what is covered"),
    Row("Inflação", "de ponta / de última geração / estado da arte",
        p(r"\bde ponta\b", r"\bde última geração\b", r"\bestado da arte\b"), True,
        "É um modelo de ponta."),
    Row("Inflação", "sem atrito",
        p(r"\bsem atrito\b"), True, "A migração é sem atrito."),
    Row("Inflação", "transparente (seamless) / fluido",
        p(r"\btransparentes?\b", r"\bfluid[oa]s?\b"), False,
        why="'proxy transparente' is a term and 'fluido' can be the physics; only meaning tells"),
    Row("Inflação", "alavancar / potencializar / impulsionar",
        # the verb forms only: "alavanca" is also the noun, the lever of a bandit
        p(r"\balavanc(?:ar\w*|ou|aram|am|ando|ad[oa]s?|amos)\b", r"\balavanqu\w+",
          r"\bpotencializ\w+", r"\bimpulsion(?:ar\w*|ou|aram|am|ando|ad[oa]s?|a)\b"), True,
        "O cache vai alavancar a venda."),
    Row("Inflação", "crucial / fundamental / essencial / primordial (como ênfase)",
        p(r"\bcruci(?:al|ais)\b", r"\bfundamenta(?:l|is)\b", r"\bessencia(?:l|is)\b",
          r"\bprimordia(?:l|is)\b"), False,
        why="'teorema fundamental' is a term, and the row is out only as emphasis"),
    Row("Inflação", "divisor de águas / revolucionário",
        p(r"\bdivisor de águas\b", r"\brevolucionári[oa]s?\b"), True,
        "O cache é revolucionário."),
    Row("Inflação", "transformador",
        p(r"\btransformador(?:a|es|as)?\b"), False,
        why="a transformer (electric, or the neural network) is a thing, not a praise"),
    Row("Inflação", "ecossistema (metáfora)",
        p(r"\becossistemas?\b"), False,
        why="an ecosystem in biology is literal; the metaphor is meaning"),
    Row("Inflação", "não é só X, é Y (contraste fabricado)",
        p(r"\bnão (?:é|são) (?:só|apenas|somente)\b.{0,80}?\b(?:é|são)\b"), False,
        why="the contrast is fabricated only if nobody said it was only X; that is the context"),
]

# "O que fica": forms the catalogue keeps. A hit inside one of them is not a hit.
KEEP = re.compile(
    r"\bestimador(?:es)? robust[oa]s?\b|\bteorema fundamental\b|\bestado fundamental\b"
    r"|\bproxy transparente\b|\bcontamos com (?:vocês|você|todos)\b", re.IGNORECASE)
CITED = re.compile(r"\[@[^\]]*\]|@[A-Za-z][\w:-]*|https?://")   # "a fonte": the row is satisfied


def hits(row: Row, unit: Unit, level: str) -> list[str]:
    found = []
    # "Contamos com vocês" is courtesy that only level leve allows ("O que fica", last item).
    keep = [m.span() for m in KEEP.finditer(unit.prose)
            if level == "leve" or not m.group(0).lower().startswith("contamos")]
    for m in row.pattern.finditer(unit.prose):
        if any(a <= m.start() < b for a, b in keep):
            continue
        if row.section == "Enchimento" and "estudos" in row.avoid and CITED.search(unit.raw):
            continue
        found.append(m.group(0).strip())
    return found


def prove(rows: list[Row], units: list[Unit], level: str) -> tuple[bool, list[tuple[Unit, Row]]]:
    """Ask Z3 for a (row, sentence) with a hit. Returns (holds, the pairs of the model)."""
    solver = Solver()
    broken, pairs = [], []
    for i, row in enumerate(rows):
        for j, unit in enumerate(units):
            h = Int(f"h[{i}][{j}]")
            solver.add(h == IntVal(len(hits(row, unit, level))))
            broken.append(h > 0)
            pairs.append((unit, row))
    solver.add(Or(*broken) if broken else BoolVal(False))
    if solver.check() != sat:
        return True, []
    model = solver.model()
    return False, [pair for pair, b in zip(pairs, broken) if model.eval(b)]


def level_arg() -> str:
    if "--level" in sys.argv:
        level = sys.argv[sys.argv.index("--level") + 1]
        if level not in SECTIONS["Sempre sai"]:
            sys.exit(f"unknown level {level!r}: leve, descritivo or estrito")
        return level
    return LEVEL


# Texts that look like a break and are not: "O que fica", and words near a row's phrase.
GOOD = ("O estimador robusto usa a mediana. O teorema fundamental vale. "
        "O cache expira em 60 s. O conector faz a ligação, e a ideia é clara. "
        "A fila é o gargalo. O relatório de 2026-03 mostra 14 falhas. "
        "Claro que o cache expira, e o sistema tem 3 nós. Puxe a alavanca do braço 2.")


def self_test() -> int:
    bad = 0
    for row in CATALOGUE:
        if not row.decided:
            continue
        units, _ = split_sentences([(1, row.bad)], "self-test")
        if prove([row], units, "estrito")[0]:
            bad += 1
            print(f"FAIL  self-test: {row.avoid!r} accepts {row.bad!r}")
    units, _ = split_sentences([(1, GOOD)], "self-test")
    holds, pairs = prove([r for r in CATALOGUE if r.decided], units, "estrito")
    if not holds:
        bad += 1
        for unit, row in pairs:
            print(f"FAIL  self-test: {row.avoid!r} rejects {unit.raw!r}")
    units, _ = split_sentences([(1, "Contamos com vocês.")], "self-test")
    if not prove([r for r in CATALOGUE if "conta com" in r.avoid], units,
                 "leve")[0]:
        bad += 1
        print("FAIL  self-test: 'Contamos com vocês' is rejected at level leve")
    decided = sum(r.decided for r in CATALOGUE)
    print(f"OK    self-test: each of the {decided} decided rows rejects its bad text, and the "
          "'O que fica' text passes" if not bad else f"\n{bad} self-test failure(s)")
    return 1 if bad else 0


def review(sentences: list[Unit], level: str) -> None:
    print("\nRows that Z3 cannot decide (their qualifier is meaning): read these sentences.")
    for row in CATALOGUE:
        if row.decided:
            continue
        status = SECTIONS[row.section][level]
        print(f"\n{row.section} ({status} at {level}): {row.avoid}. {row.why}.")
        found = [u for u in sentences if hits(row, u, level)]
        for u in found:
            snippet = u.raw if len(u.raw) <= 100 else u.raw[:97] + "..."
            print(f"  {u.file}:{u.line}  [{', '.join(dict.fromkeys(hits(row, u, level)))}]  "
                  f"{snippet}")
        print(f"  ({len(found)} sentences)")


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    level = level_arg()
    sentences, _ = read_script()
    print(f"PTC-9 noise catalogue ({SOURCE}), level {level}: {len(sentences)} sentences in "
          f"{SCRIPT.relative_to(ROOT)}/")
    failed = 0
    for section, levels in SECTIONS.items():
        rows = [r for r in CATALOGUE if r.section == section and r.decided]
        holds, broken = prove(rows, sentences, level)
        status = levels[level]
        tag = "OK  " if holds else {"required": "FAIL", "recommended": "NOTE", "off": "OFF "}[status]
        print(f"{tag}  {section}: {len(rows)} decided rows, {status} at {level} "
              f"({'unsat' if holds else 'sat'})")
        for unit, row in broken:
            print(f"        {unit.file}:{unit.line}: {', '.join(dict.fromkeys(hits(row, unit, level)))}"
                  f"  ({row.avoid})")
        if not holds and status == "required":
            failed += 1
    undecided = sum(not r.decided for r in CATALOGUE)
    print(f"      {undecided} rows need a reader: python3 z3/ruido_ia.py --review")
    if "--review" in sys.argv:
        review(sentences, level)
    if failed:
        print(f"\n{failed} required table(s) of the noise catalogue fail")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
