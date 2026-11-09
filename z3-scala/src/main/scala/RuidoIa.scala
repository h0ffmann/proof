// The PTC-9 noise catalogue (references/ruido-ia.md), checked on the video script with Z3.
//
// PTC-9 says: if a passage goes and no fact, condition or instruction is lost, it is noise. The PTC
// repository (kayquer/portugues-tecnico-controlado, references/ruido-ia.md) lists where that noise
// usually shows up in technical text written or revised by a model, in four tables:
//
//     Sempre sai        out at every level, `leve` too            required at leve
//     Enchimento        out at estrito and descritivo             recommended at leve
//     Evasão de cópula  out at estrito and descritivo             off at leve
//     Inflação          out at estrito and descritivo             off at leve
//
// Ptc.scala already checks a short form of PTC-9 (NOISE_ALWAYS, NOISE_FILLER). This check covers
// the catalogue itself, entry by entry, so that a change to the catalogue is a change to one row
// of CATALOGUE below. Each row is either:
//
// - decided: the "Evite" phrase is a break wherever it stands, except in the forms that the
//   catalogue's "O que fica" section keeps (KEEP). For every sentence s and every such row e, the
//   number of hits is a Z3 constant h[e][s]. Z3 is asked for a model of "some h[e][s] > 0". unsat
//   means that no sentence breaks the table.
// - read: the row has a qualifier that needs the meaning of the sentence ("no sentido de ter",
//   "sem relação causal", "como ênfase"). No formula over the text decides it, so --review lists
//   the sentences that carry the phrase, for a person to read.
//
//     z3-scala/z3.sh ruido-ia                 # one line per table; exit 1 if a required table fails
//     z3-scala/z3.sh ruido-ia --self-test     # every decided row rejects its bad text, KEEP passes
//     z3-scala/z3.sh ruido-ia --review        # also the sentences a person must read, row by row
//     z3-scala/z3.sh ruido-ia --level estrito # the level (default: leve, 00-como-ler.md, line 4)
//
// The protected zone (code, URLs, quotations, italic foreign words) is taken out first, as in
// Ptc.scala, whose reader this check uses.
package z3scala

import com.microsoft.z3.Status

import java.util.regex.Pattern

import Z.*
import Ptc.{LEVEL, ROOT, SCRIPT, Unit, readScript, splitSentences}

object RuidoIa:
  val SOURCE = "kayquer/portugues-tecnico-controlado, references/ruido-ia.md (PTC 1.2.0)"

  // Section -> {level: "required" | "recommended" | "off"} (the line under each table heading).
  val SECTIONS: List[(String, Map[String, String])] = List(
    "Sempre sai" -> Map("leve" -> "required", "descritivo" -> "required", "estrito" -> "required"),
    "Enchimento" -> Map("leve" -> "recommended", "descritivo" -> "required", "estrito" -> "required"),
    "Evasão de cópula" -> Map("leve" -> "off", "descritivo" -> "required", "estrito" -> "required"),
    "Inflação" -> Map("leve" -> "off", "descritivo" -> "required", "estrito" -> "required")
  )

  /**
   * A row of the catalogue. avoid: the "Evite" cell, as in ruido-ia.md; decided: Z3 decides it, else a person
   * reads the candidates; bad: a sentence a decided row must reject (self-test); why: for a read row, what Z3
   * would need to know.
   */
  final case class Row(
      section: String,
      avoid: String,
      pattern: Pattern,
      decided: Boolean,
      bad: String = "",
      why: String = ""
  )

  def p(alternatives: String*): Pattern =
    Py.re(alternatives.map(a => s"(?:$a)").mkString("(?:", "|", ")"), ignoreCase = true)
  def start(alternatives: String*): Pattern =
    Py.re(alternatives.map(a => s"(?:$a)").mkString("^\\W*(?:", "|", ")"), ignoreCase = true)

  val CATALOGUE: List[Row] = List(
    // Sempre sai
    Row(
      "Sempre sai",
      "Claro! / Com certeza! / Perfeito!",
      p("\\bclaro\\s*!", "\\bcom certeza\\s*!", "\\bperfeito\\s*!"),
      true,
      "Claro! O serviço reinicia em 5 s."
    ),
    Row(
      "Sempre sai",
      "Ótima pergunta / Excelente observação",
      p("\\b(?:ótima|excelente|boa) pergunta\\b", "\\b(?:ótima|excelente) observação\\b"),
      true,
      "Ótima pergunta, o serviço reinicia em 5 s."
    ),
    Row(
      "Sempre sai",
      "Espero ter ajudado / Espero que isso ajude",
      p("\\bespero (?:ter ajudado|que (?:isso )?(?:ajude|tenha ajudado))\\b"),
      true,
      "O serviço reinicia em 5 s. Espero que isso ajude."
    ),
    Row(
      "Sempre sai",
      "Fique à vontade para / Qualquer dúvida, estou à disposição",
      p(
        "\\bfique à vontade para\\b",
        "\\bqualquer dúvida,? estou à disposição\\b",
        "\\bestou à disposição\\b"
      ),
      true,
      "Fique à vontade para abrir um chamado."
    ),
    Row(
      "Sempre sai",
      "Vamos lá / Vamos explorar / Vamos entender",
      p("\\bvamos (?:lá|explorar|entender)\\b"),
      true,
      "Vamos entender o cache."
    ),
    Row(
      "Sempre sai",
      "Vamos + another verb (the same false collaborative opening)",
      p("\\bvamos (?!lá\\b|explorar\\b|entender\\b)\\w+"),
      false,
      why = "the table names three verbs; with another verb, whether the opening delays the " +
        "subject or is the subject is meaning, and 1st person is allowed at leve"
    ),
    Row(
      "Sempre sai",
      "Neste documento, vamos abordar… / A seguir, veremos…",
      p("\\bneste (?:documento|texto|artigo|vídeo),? vamos\\b", "\\ba seguir,? veremos\\b"),
      true,
      "Neste documento, vamos abordar o cache."
    ),
    Row(
      "Sempre sai",
      "Em resumo, vimos que…",
      p("\\bem resumo,? vimos\\b"),
      true,
      "Em resumo, vimos que o cache expira."
    ),
    Row(
      "Sempre sai",
      "Com base nas informações disponíveis / Até onde sei",
      p("\\bcom base nas informações disponíveis\\b", "\\baté onde (?:eu )?sei\\b"),
      true,
      "Até onde sei, o cache expira em 60 s."
    ),
    Row(
      "Sempre sai",
      "O futuro é promissor / Só o tempo dirá / Uma coisa é certa",
      p("\\bo futuro é promissor\\b", "\\bsó o tempo dirá\\b", "\\buma coisa é certa\\b"),
      true,
      "Só o tempo dirá."
    ),
    Row(
      "Sempre sai",
      "Vou analisar passo a passo / Pensando nisso de forma estruturada",
      p("\\bvou analisar passo a passo\\b", "\\bpensando nisso de forma estruturada\\b"),
      true,
      "Vou analisar passo a passo o log."
    ),

    // Enchimento
    Row(
      "Enchimento",
      "além disso / ademais / outrossim (abrindo frase)",
      start("além disso\\b", "ademais\\b", "outrossim\\b"),
      true,
      "Além disso, o cache expira."
    ),
    Row(
      "Enchimento",
      "além disso / ademais / outrossim (no meio da frase)",
      p("\\balém disso\\b", "\\bademais\\b", "\\boutrossim\\b"),
      false,
      why = "inside a sentence the connector may add a real second item; only the meaning tells"
    ),
    Row(
      "Enchimento",
      "nesse sentido / dessa forma / desse modo (sem relação causal)",
      p("\\bnesse sentido\\b", "\\bdess[ae] (?:forma|modo|maneira)\\b"),
      false,
      why = "'O que fica' keeps it when it marks a real consequence; causality is meaning"
    ),
    Row(
      "Enchimento",
      "quando se trata de X",
      p("\\bquando se trata de\\b"),
      true,
      "Quando se trata de cache, o TTL é 60 s."
    ),
    Row(
      "Enchimento",
      "no cenário atual / nos dias de hoje / em um mundo cada vez mais…",
      p("\\bno cenário atual\\b", "\\bnos dias de hoje\\b", "\\bem um mundo cada vez mais\\b"),
      true,
      "No cenário atual, o cache expira em 60 s."
    ),
    Row(
      "Enchimento",
      "em suma / em síntese / em conclusão",
      p("\\bem (?:suma|síntese|conclusão)\\b"),
      true,
      "Em suma, o cache expira em 60 s."
    ),
    Row(
      "Enchimento",
      "vale destacar / cabe ressaltar / é importante mencionar",
      p(
        "\\b(?:vale|cabe) (?:a pena )?(?:destacar|ressaltar|mencionar|lembrar|notar)\\b",
        "\\bé importante (?:mencionar|destacar|ressaltar|notar|lembrar)\\b"
      ),
      true,
      "Vale destacar que o cache expira em 60 s."
    ),
    Row(
      "Enchimento",
      "notavelmente / curiosamente / surpreendentemente",
      p("\\b(?:notavelmente|curiosamente|surpreendentemente)\\b"),
      true,
      "Curiosamente, o cache expira em 60 s."
    ),
    Row(
      "Enchimento",
      "sem dúvida / certamente / de fato / indiscutivelmente",
      p("\\bsem dúvida\\b", "\\bcertamente\\b", "\\bde fato\\b", "\\bindiscutivelmente\\b"),
      true,
      "O cache, sem dúvida, expira em 60 s."
    ),
    Row(
      "Enchimento",
      "estudos mostram / especialistas apontam / pesquisas indicam",
      p(
        "\\b(?:estudos|especialistas|pesquisas|pesquisadores)" +
          " (?:mostram|apontam|indicam|sugerem|dizem)\\b"
      ),
      true,
      "Estudos mostram que o cache ajuda."
    ),
    Row(
      "Enchimento",
      "é sabido que / é consenso que",
      p("\\bé (?:sabido|consenso|notório) que\\b"),
      true,
      "É sabido que o cache ajuda."
    ),

    // Evasão de cópula
    Row(
      "Evasão de cópula",
      "atua como / funciona como / se configura como",
      p("\\b(?:atua|atuam|funciona|funcionam) como\\b", "\\bse configura(?:m)? como\\b"),
      true,
      "O Redis atua como cache."
    ),
    Row(
      "Evasão de cópula",
      "conta com / dispõe de / possui",
      p("\\bconta(?:m)? com\\b", "\\bdispõe(?:m)? de\\b", "\\bposs(?:ui|uem|uir)\\b"),
      true,
      "O cluster conta com 3 nós."
    ),
    Row(
      "Evasão de cópula",
      "apresenta (no sentido de ter)",
      p("\\bapresenta(?:m)?\\b"),
      false,
      why = "'apresentar erro' and 'apresentar ao público' are other senses; the sense is meaning"
    ),
    Row(
      "Evasão de cópula",
      "representa (no sentido de ser)",
      p("\\brepresenta(?:m)?\\b"),
      false,
      why = "'a seta representa o fluxo' (a symbol stands for a thing) is not a copula"
    ),
    Row(
      "Evasão de cópula",
      "se destaca por",
      p("\\bse destaca(?:m)? (?:por|pel[oa]s?)\\b"),
      true,
      "O Redis se destaca pela latência."
    ),

    // Inflação
    Row(
      "Inflação",
      "robusto (elogio vago)",
      p("\\brobust[oa]s?\\b"),
      false,
      why = "'estimador robusto' is a term; a vague praise needs the absence of a criterion"
    ),
    Row(
      "Inflação",
      "abrangente / completo (sem dizer o que cobre)",
      p("\\babrangentes?\\b", "\\bcomplet[oa]s?\\b"),
      false,
      why = "the row is out only when the text does not say what is covered"
    ),
    Row(
      "Inflação",
      "de ponta / de última geração / estado da arte",
      p("\\bde ponta\\b", "\\bde última geração\\b", "\\bestado da arte\\b"),
      true,
      "É um modelo de ponta."
    ),
    Row("Inflação", "sem atrito", p("\\bsem atrito\\b"), true, "A migração é sem atrito."),
    Row(
      "Inflação",
      "transparente (seamless) / fluido",
      p("\\btransparentes?\\b", "\\bfluid[oa]s?\\b"),
      false,
      why = "'proxy transparente' is a term and 'fluido' can be the physics; only meaning tells"
    ),
    Row(
      "Inflação",
      "alavancar / potencializar / impulsionar",
      // the verb forms only: "alavanca" is also the noun, the lever of a bandit
      p(
        "\\balavanc(?:ar\\w*|ou|aram|am|ando|ad[oa]s?|amos)\\b",
        "\\balavanqu\\w+",
        "\\bpotencializ\\w+",
        "\\bimpulsion(?:ar\\w*|ou|aram|am|ando|ad[oa]s?|a)\\b"
      ),
      true,
      "O cache vai alavancar a venda."
    ),
    Row(
      "Inflação",
      "crucial / fundamental / essencial / primordial (como ênfase)",
      p(
        "\\bcruci(?:al|ais)\\b",
        "\\bfundamenta(?:l|is)\\b",
        "\\bessencia(?:l|is)\\b",
        "\\bprimordia(?:l|is)\\b"
      ),
      false,
      why = "'teorema fundamental' is a term, and the row is out only as emphasis"
    ),
    Row(
      "Inflação",
      "divisor de águas / revolucionário",
      p("\\bdivisor de águas\\b", "\\brevolucionári[oa]s?\\b"),
      true,
      "O cache é revolucionário."
    ),
    Row(
      "Inflação",
      "transformador",
      p("\\btransformador(?:a|es|as)?\\b"),
      false,
      why = "a transformer (electric, or the neural network) is a thing, not a praise"
    ),
    Row(
      "Inflação",
      "ecossistema (metáfora)",
      p("\\becossistemas?\\b"),
      false,
      why = "an ecosystem in biology is literal; the metaphor is meaning"
    ),
    Row(
      "Inflação",
      "não é só X, é Y (contraste fabricado)",
      p("\\bnão (?:é|são) (?:só|apenas|somente)\\b.{0,80}?\\b(?:é|são)\\b"),
      false,
      why = "the contrast is fabricated only if nobody said it was only X; that is the context"
    )
  )

  // "O que fica": forms the catalogue keeps. A hit inside one of them is not a hit.
  val KEEP: Pattern = Py.re(
    "\\bestimador(?:es)? robust[oa]s?\\b|\\bteorema fundamental\\b|\\bestado fundamental\\b" +
      "|\\bproxy transparente\\b|\\bcontamos com (?:vocês|você|todos)\\b",
    ignoreCase = true
  )
  val CITED: Pattern = Py.re("\\[@[^\\]]*\\]|@[A-Za-z][\\w:-]*|https?://") // "a fonte": the row is satisfied

  def hits(row: Row, unit: Unit, level: String): List[String] =
    // "Contamos com vocês" is courtesy that only level leve allows ("O que fica", last item).
    val keep = Py
      .matches(KEEP, unit.prose)
      .filter(m => level == "leve" || !m.group().toLowerCase.startsWith("contamos"))
      .map(m => (m.start, m.end))
    Py.matches(row.pattern, unit.prose)
      .filterNot(m => keep.exists((a, b) => a <= m.start && m.start < b))
      .filterNot(_ =>
        row.section == "Enchimento" && row.avoid.contains("estudos") && Py.search(CITED, unit.raw)
      )
      .map(m => Py.strip(m.group()))

  /** Ask Z3 for a (row, sentence) with a hit. Returns (holds, the pairs of the model). */
  def prove(rows: List[Row], units: List[Unit], level: String): (Boolean, List[(Unit, Row)]) =
    val solver = ctx.mkSolver()
    val cells = for (row, i) <- rows.zipWithIndex; (unit, j) <- units.zipWithIndex yield
      val h = int(s"h[$i][$j]")
      solver.add(h === intVal(hits(row, unit, level).size))
      (h > intVal(0), (unit, row))
    solver.add(if cells.nonEmpty then or(cells.map(_._1)*) else False)
    if solver.check() != Status.SATISFIABLE then (true, Nil)
    else
      val model = solver.getModel
      (false, cells.collect { case (b, pair) if model.eval(b, false).isTrue => pair })

  def levelArg(args: Seq[String]): Either[String, String] =
    val i = args.indexOf("--level")
    if i < 0 then Right(LEVEL)
    else
      val level = args.lift(i + 1).getOrElse("")
      if SECTIONS.head._2.contains(level) then Right(level)
      else Left(s"unknown level ${Py.repr(level)}: leve, descritivo or estrito")

  // Texts that look like a break and are not: "O que fica", and words near a row's phrase.
  val GOOD: String = "O estimador robusto usa a mediana. O teorema fundamental vale. " +
    "O cache expira em 60 s. O conector faz a ligação, e a ideia é clara. " +
    "A fila é o gargalo. O relatório de 2026-03 mostra 14 falhas. " +
    "Claro que o cache expira, e o sistema tem 3 nós. Puxe a alavanca do braço 2."

  def selfTest(): Int =
    var bad = 0
    for row <- CATALOGUE if row.decided do
      val (units, _) = splitSentences(List((1, row.bad)), "self-test")
      if prove(List(row), units, "estrito")._1 then
        bad += 1
        println(s"FAIL  self-test: ${Py.repr(row.avoid)} accepts ${Py.repr(row.bad)}")
    val (goodUnits, _) = splitSentences(List((1, GOOD)), "self-test")
    val (holds, pairs) = prove(CATALOGUE.filter(_.decided), goodUnits, "estrito")
    if !holds then
      bad += 1
      for (unit, row) <- pairs do
        println(s"FAIL  self-test: ${Py.repr(row.avoid)} rejects ${Py.repr(unit.raw)}")
    val (courtesy, _) = splitSentences(List((1, "Contamos com vocês.")), "self-test")
    if !prove(CATALOGUE.filter(_.avoid.contains("conta com")), courtesy, "leve")._1 then
      bad += 1
      println("FAIL  self-test: 'Contamos com vocês' is rejected at level leve")
    val decided = CATALOGUE.count(_.decided)
    println(if bad == 0 then
      s"OK    self-test: each of the $decided decided rows rejects its bad text, and the " +
        "'O que fica' text passes"
    else s"\n$bad self-test failure(s)")
    if bad > 0 then 1 else 0

  def review(sentences: List[Unit], level: String): scala.Unit =
    println("\nRows that Z3 cannot decide (their qualifier is meaning): read these sentences.")
    for row <- CATALOGUE if !row.decided do
      val status = SECTIONS.toMap.apply(row.section)(level)
      println(s"\n${row.section} ($status at $level): ${row.avoid}. ${row.why}.")
      val found = sentences.filter(u => hits(row, u, level).nonEmpty)
      for u <- found do
        println(
          s"  ${u.file}:${u.line}  [${hits(row, u, level).distinct.mkString(", ")}]  ${Ptc.snippet(u.raw)}"
        )
      println(s"  (${found.size} sentences)")

  def run(args: Seq[String]): Int =
    if args.contains("--self-test") then selfTest()
    else
      levelArg(args) match
        case Left(message) =>
          System.err.println(message)
          1
        case Right(level) => check(args, level)

  def check(args: Seq[String], level: String): Int =
    val (sentences, _) = readScript()
    println(
      s"PTC-9 noise catalogue ($SOURCE), level $level: ${sentences.size} sentences in " +
        s"${ROOT.relativize(SCRIPT)}/"
    )
    var failed = 0
    for (section, levels) <- SECTIONS do
      val rows = CATALOGUE.filter(r => r.section == section && r.decided)
      val (holds, broken) = prove(rows, sentences, level)
      val status = levels(level)
      val tag =
        if holds then "OK  " else Map("required" -> "FAIL", "recommended" -> "NOTE", "off" -> "OFF ")(status)
      println(
        s"$tag  $section: ${rows.size} decided rows, $status at $level " +
          s"(${if holds then "unsat" else "sat"})"
      )
      for (unit, row) <- broken do
        println(
          s"        ${unit.file}:${unit.line}: ${hits(row, unit, level).distinct.mkString(", ")}  (${row.avoid})"
        )
      if !holds && status == "required" then failed += 1
    val undecided = CATALOGUE.count(!_.decided)
    println(s"      $undecided rows need a reader: z3-scala/z3.sh ruido-ia --review")
    if args.contains("--review") then review(sentences, level)
    if failed > 0 then
      println(s"\n$failed required table(s) of the noise catalogue fail")
      1
    else 0
