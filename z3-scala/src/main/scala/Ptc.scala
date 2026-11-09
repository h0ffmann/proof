// The PTC rules of the video script, checked with Z3.
//
// The video script (papers/contextual-bandits/script/prose-pt-BR/) is written in Portuguese
// Técnico Controlado (PTC, kayquer/portugues-tecnico-controlado, version 1.2.0), level `leve`, for
// a human reader (00-como-ler.md, lines 3 to 6). PTC has nine rules. At level `leve` some parts of
// them are required, some are recommended, and some are off (the level table of the PTC SKILL.md).
//
// This check takes the part of each rule that a program can measure on the text: a sentence
// length, a spelling, a number format, a phrase. For every sentence (or paragraph) of the script it
// measures that value, gives it to Z3 as a constant, states the rule as a formula over all the
// sentences, and asks Z3 for a model of the negation. "unsat" means that no sentence breaks the
// rule. "sat" gives the sentences that do, from the model.
//
//     z3-scala/z3.sh ptc               # one line per check; exit code 1 if a required check fails
//     z3-scala/z3.sh ptc --self-test   # each required check rejects a bad text, accepts a good one
//     z3-scala/z3.sh ptc --review      # also list the sentences a person must read, for each rule
//                                      # (or part of a rule) that Z3 cannot decide
//
// The text that PTC protects is taken out before the checks (SKILL.md, "Processo", step 3): code
// (inline and fenced), file names, URLs, citation keys, and text in quotation marks (a quotation,
// or a label on the screen). A sentence keeps all its words for the length check.
//
// What Z3 cannot decide, and why, is in z3-scala/README.md, "PTC rules that Z3 cannot prove".
package z3scala

import com.microsoft.z3.Status

import java.nio.file.{Files, Path, Paths}
import java.util.regex.Pattern
import scala.jdk.CollectionConverters.*

import Z.*
import Py.re

object Ptc:
  val ROOT: Path = Paths.get("").toAbsolutePath
  val SCRIPT: Path = ROOT.resolve("papers/contextual-bandits/script/prose-pt-BR")
  val LEVEL = "leve" // 00-como-ler.md, line 4
  val MAX_WORDS = 35 // PTC-5 at level leve, and 00-como-ler.md, line 6
  val MAX_SENTENCES = 6 // sentences per paragraph (recommended at level leve)

  // -------------------------------------------------------------------------------------------
  // Reading the script: paragraphs, sentences, and the protected zone

  /**
   * A sentence (or a paragraph), with its place in the script. text: the words as written, code and
   * quotations masked as one word each; prose: the same, with the quotations taken out too (what the rules
   * apply to); raw: the sentence as written, for the report.
   */
  final case class Unit(file: String, line: Int, text: String, prose: String, raw: String = "")

  type Lines = List[(Int, String)]

  val FENCE = re("^(```|~~~)")
  val DIV = re("^:::")
  val HEADING_ATTR = re("\\{[.#][^}]*\\}")
  val INLINE_CODE = re("`[^`\\n]*`")
  val URL = re("<?https?://\\S+?>?(?=[\\s)\\]]|$)")
  val CITATION = re("\\[@[^\\]]*\\]|@[A-Za-z][\\w:-]*")
  val QUOTE = re("\"[^\"\\n]*\"|“[^”\\n]*”")
  val EMPHASIS = re("\\*\\*([^*\\n]+?)\\*\\*")
  val ITALIC = re("(?<![*\\w])\\*([^*\\n]+?)\\*(?![*\\w])") // a foreign word or a title
  val LABEL = re("^\\*\\*[^*]+\\.\\*\\*\\s*") // **Fala.**, **Tela.**, **Código.**
  val LIST_ITEM = re("^\\s*(?:[-*+]|\\d+\\.)\\s+")
  val TABLE_RULE = re("^\\|?[\\s:|-]+\\|?$")
  val CAPTION = re("^:\\s+")
  // A sentence ends at . ! ? or … (and a closing quotation mark, bracket or code mark) before a
  // space and a capital letter, a digit, a quotation mark, a bracket, a code mark or an emphasis.
  // Abbreviations that end with a point are not ends.
  val SENTENCE_END = re(
    "(?:(?<=[.!?…])|(?<=[.!?…][`\"”)\\]])|(?<=[.!?…]\\][`]))\\s+" +
      "(?=[\"“(\\[*`⚠A-ZÁÉÍÓÚÂÊÔÃÕÇπ0-9])"
  )
  // An inline list: "1952 Robbins · 2010 LinUCB · ...". Each item is a unit, as in a list.
  val INLINE_LIST = re("\\s+·\\s+")
  val ABBREVIATION = re("\\b(?:p|ex|Sr|Sra|Dr|Dra|etc|vs|cf|N|nº)\\.$", ignoreCase = true)
  val WORD = re("[^\\s|·—–⚠*]+")
  val KEY = re("^(\\w[\\w-]*):\\s*(.*)$")
  val HAS_WORD = re("\\w")

  /** Protected zone (code, URL, citation) becomes one word: X. */
  def mask(text: String): String =
    var t = Py.sub(INLINE_CODE, " X ", text)
    t = Py.sub(URL, " X ", t)
    Py.sub(CITATION, " ", t) // a citation is not a word of the sentence

  /** The prose of a YAML front matter: title, subtitle and abstract. Returns (lines, end). */
  def frontMatter(lines: Vector[String]): (Lines, Int) =
    if lines.isEmpty || Py.strip(lines(0)) != "---" then (Nil, 0)
    else
      val out = List.newBuilder[(Int, String)]
      var key = ""
      val body = lines.drop(1).zipWithIndex.map((l, i) => (l, i + 2))
      val end = body.find((line, _) => Py.strip(line) == "---").map(_._2)
      for (line, n) <- body.takeWhile((_, n) => end.forall(n < _)) do
        Py.matchStart(KEY, line) match
          case Some(m) =>
            key = m.group(1)
            val value = Py.strip(m.group(2))
            if (key == "title" || key == "subtitle") && value.nonEmpty then
              out += ((n, Py.strip(value, "\"'") + "."))
              out += ((n, ""))
          case None =>
            if key == "abstract" then out += ((n, Py.strip(line)))
      (out.result(), end.getOrElse(lines.size))

  /** Blocks of prose lines, with line numbers. A list item and a table cell are blocks. */
  def paragraphs(path: Path): List[Lines] =
    val lines = Py.splitlines(Py.readText(path)).toVector
    val (head, start) = frontMatter(lines)
    val numbered = head ++ lines.drop(start).zipWithIndex.map((l, i) => (i + start + 1, l))
    val blocks = List.newBuilder[Lines]
    var current = List.empty[(Int, String)] // reversed
    var inCode = false
    def flush(): scala.Unit =
      if current.nonEmpty then blocks += current.reverse
      current = Nil
    for (n, line) <- numbered do
      val stripped = Py.strip(line)
      if Py.matchStart(FENCE, stripped).isDefined then
        inCode = !inCode
        flush()
      else if inCode || Py.matchStart(DIV, stripped).isDefined then ()
      else if stripped.isEmpty then flush()
      else if stripped.startsWith("#") then
        flush()
        val title = Py.strip(Py.sub(HEADING_ATTR, "", Py.lstrip(stripped, "#")))
        if title.nonEmpty then blocks += List((n, title))
      else if stripped.startsWith("|") then
        flush()
        if Py.matchStart(TABLE_RULE, stripped).isEmpty then
          for cell <- Py.strip(stripped, "|").split("\\|", -1) if Py.strip(cell).nonEmpty do
            blocks += List((n, Py.strip(cell)))
      else if Py.matchStart(LIST_ITEM, line).isDefined then
        flush()
        current = List((n, Py.sub(LIST_ITEM, "", line)))
      else if Py.matchStart(CAPTION, stripped).isDefined then
        flush()
        current = List((n, Py.sub(CAPTION, "", stripped)))
      else current = (n, stripped) :: current
    flush()
    blocks.result()

  /**
   * The sentences of one block, each with the line where it starts, and the number of sentences (an inline
   * list gives one unit per item, but it is one sentence).
   */
  def splitSentences(block: Lines, file: String): (List[Unit], Int) =
    val sb = new StringBuilder
    val starts = List.newBuilder[(Int, Int)]
    for (n, line) <- block do
      starts += ((sb.length, n))
      sb.append(line).append(' ')
    val text = sb.toString
    val startList = starts.result()
    val offset = Py.matchStart(LABEL, text).map(_.end).getOrElse(0)
    val units = List.newBuilder[Unit]
    var count = 0
    var pieceStart = offset
    val m = SENTENCE_END.matcher(text)
    val ends = Iterator
      .unfold(offset)(from =>
        if from <= text.length && m.find(from) then Some((Some((m.start, m.end)), m.end)) else None
      )
      .toList :+ None
    for e <- ends do
      val end = e.map(_._1).getOrElse(text.length)
      val piece = Py.strip(text.substring(pieceStart, end max pieceStart))
      if e.isDefined && Py.search(ABBREVIATION, piece) then ()
      else
        val line = if piece.nonEmpty then startList.filter(_._1 <= pieceStart).map(_._2).max else 0
        if piece.nonEmpty then count += 1
        if piece.nonEmpty then
          for item <- INLINE_LIST.split(piece, -1) do
            val masked = mask(Py.sub(EMPHASIS, "$1", item))
            val prose = Py.sub(ITALIC, " Q ", Py.sub(QUOTE, " Q ", masked))
            units += Unit(file, line, Py.sub(ITALIC, "$1", masked), prose, item)
        e.foreach(x => pieceStart = x._2)
    (units.result(), count)

  /** (sentences, paragraphs) of every Markdown file of the script. */
  def readScript(): (List[Unit], List[Unit]) =
    val sentences = List.newBuilder[Unit]
    val paras = List.newBuilder[Unit]
    val files =
      Files.list(SCRIPT).iterator.asScala.filter(_.toString.endsWith(".md")).toList.sortBy(_.toString)
    for path <- files do
      val name = ROOT.relativize(path).toString
      for block <- paragraphs(path) do
        val (units, count) = splitSentences(block, name)
        sentences ++= units
        if units.nonEmpty then
          paras += Unit(name, units.head.line, units.map(_.text).mkString(" "), count.toString)
    (sentences.result(), paras.result())

  def words(unit: Unit): Int = Py.findAll(WORD, unit.text).count(w => Py.search(HAS_WORD, w))

  // -------------------------------------------------------------------------------------------
  // The rules, as patterns over the prose (the protected zone is already out)

  def anyOf(patterns: Seq[String], ignoreCase: Boolean = true): Pattern =
    re(patterns.map(p => s"(?:$p)").mkString("|"), ignoreCase)

  val VOWEL = "aeiouáéíóúâêôãõ"
  // PTC-8: prefixes that end in a vowel (SKILL.md, PTC-8; references/ortografia-ptbr.md)
  val PREFIX_V =
    "(?:micro|auto|anti|contra|semi|mini|ultra|infra|extra|multi|intra|neo|pseudo|proto|retro|macro|mega|poli|tele|hidro|termo|eletro|foto|geo|bio|socio)"
  val SPELLING = anyOf(
    Seq(
      "\\b(?:idéia|assembléia|heróico|jibóia|geléia|européia|européias|platéia|estréia|" +
        "apóia|bóia|paranóia|epopéia|colméia|alcatéia|asteróide|onomatopéia|" +
        "jóia|jóias|idéias|heróicos|heróica)\\b", // open diphthong in a paroxytone
      "\\b(?:vôo|vôos|enjôo|enjôos|lêem|crêem|vêem|dêem|relêem|prevêem|abençôo|perdôo)\\b",
      "\\b(?:pára|pêlo|pêlos|pólo|pólos|pêra)\\b", // abolished differential accents
      "\\b(?:co|re)-\\w+", // co-autor, re-escrever
      "\\bré-\\w+",
      "\\b(?:pre|pos|pro)-(?=\\w)", // pré-, pós-, pró- keep the accent
      "\\bnão-\\w+", // não-conformidade
      "\\bsubr\\w+", // subrotina -> sub-rotina
      "\\binterrela\\w*", // interrelação -> inter-relação
      "\\bsuper-(?![hr])\\w+", // super-usuário -> superusuário
      "\\binter-(?!r)\\w+", // inter-operabilidade
      "\\b" + PREFIX_V + "-[rs]\\w+", // micro-serviço -> microsserviço
      "\\b" + PREFIX_V + "[rs][" + VOWEL + "]\\w*" // microserviço -> microsserviço
    )
  )
  // prefix (ends in a vowel) + hyphen + a vowel: a hyphen only when the two vowels are the same
  val PREFIX_HYPHEN_VOWEL = re("\\b(" + PREFIX_V + ")-([" + VOWEL + "])\\w*", ignoreCase = true)
  val TREMA = re("\\b[a-zà-ú]\\w*ü\\w*") // trema, but not in a name (Müller)
  // Words that the last pattern would take and that are right.
  val SPELLING_OK = re(
    "^(?:autor\\w*|automático\\w*|micros?|microsoft|auto(?:s|res)?|antes|contrast\\w*|termos?" +
      "|bios|neos|geos|fotos|polos?|telas?|telescópio\\w*|proto|retros?|semis?|minis?|macros?" +
      "|megas?|ultras?|infras?|extras?|multis?|intras?|socios?|eletros?|hidros?)$",
    ignoreCase = true
  )

  // PTC-7: number, date, hour, unit, range
  val DECIMAL_POINT = re("(?<![\\w.,/:-])\\d+\\.\\d{1,2}(?![\\d.,])|(?<![\\w.,/:-])\\d+\\.\\d{4,}(?![\\d.,])")
  // A number with a point that is not a decimal: a scene, a version, a model, an IP-like id.
  val NUMBER_ID = re(
    "(?:\\b(?:cenas?|scene|takes?|seção|versão|v|V|Sonnet|Fable|Opus|Haiku|Claude|Lean|Z3|GHC" +
      "|OpenVoice|XTTS|Python|pandoc)\\s*(?:\\d+(?:\\.\\d+)*\\s*(?:,|e|a)\\s*)*$)",
    ignoreCase = true
  )
  val NUMBER_FORMAT = anyOf(
    Seq(
      "\\b\\d{1,3}(?:,\\d{3}){2,}\\b", // 1,000,000 (English thousands)
      "\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b", // 02/08/2026
      "\\b\\d{1,2}(?::\\d{2})?\\s?(?:AM|PM|a\\.m\\.|p\\.m\\.)(?!\\w)", // 2:30 PM
      "\\b\\d+(?:[.,]\\d+)?(?:ms|min|GB|MB|KB|TB|kB|kg|km|cm|mm|GHz|MHz|Hz|kW|W|°C|%)(?!\\w)",
      "\\b\\d+(?:[.,]\\d+)?\\s(?:kgs|kms|mins|GBs|MBs)\\b", // pluralized symbol
      "(?<![\\w-])\\d+-\\d+(?![\\w-])(?<!\\b\\d{4}-\\d{2})" // 10-20 as a range (not 2017-12)
    ),
    ignoreCase = false
  )

  // PTC-9, the part that leaves in every level: chatbot artefact, meta-text, model limit, generic end
  val NOISE_ALWAYS = anyOf(
    Seq(
      "\\bclaro!",
      "\\bcom certeza!",
      "\\bperfeito!",
      "\\b(?:ótima|boa|excelente) pergunta\\b",
      "\\bexcelente observação\\b",
      "\\bespero (?:ter ajudado|que (?:isso )?(?:ajude|tenha ajudado))\\b",
      "\\bfique à vontade para\\b",
      "\\bqualquer dúvida, estou à disposição\\b",
      "\\bvamos (?:lá|explorar|entender|mergulhar)\\b",
      "\\bneste documento, vamos\\b",
      "\\ba seguir, veremos\\b",
      "\\bem resumo, vimos\\b",
      "\\bcom base nas informações disponíveis\\b",
      "\\baté onde (?:sei|eu sei)\\b",
      "\\bo futuro é promissor\\b",
      "\\bsó o tempo dirá\\b",
      "\\buma coisa é certa\\b",
      "\\bvou analisar passo a passo\\b",
      "\\bpensando nisso de forma estruturada\\b",
      "\\bcomo (?:um )?(?:modelo de linguagem|uma IA|IA)\\b"
    )
  )

  // PTC-9, the part that is recommended at level leve: filler, confidence, vague attribution,
  // copula evasion, inflation
  val NOISE_FILLER = anyOf(
    Seq(
      "\\balém disso\\b",
      "\\bademais\\b",
      "\\boutrossim\\b",
      "\\bnesse sentido\\b",
      "\\bquando se trata de\\b",
      "\\bno cenário atual\\b",
      "\\bnos dias de hoje\\b",
      "\\bem um mundo cada vez mais\\b",
      "\\bem (?:suma|síntese|conclusão)\\b",
      "\\b(?:vale|cabe) (?:destacar|ressaltar|lembrar|mencionar)\\b",
      "\\bé importante mencionar\\b",
      "\\b(?:notavelmente|curiosamente|surpreendentemente|indiscutivelmente)\\b",
      "\\bsem dúvida\\b",
      "\\bde fato\\b",
      "\\bcertamente\\b",
      "\\b(?:estudos|especialistas|pesquisas) (?:mostram|apontam|indicam)\\b",
      "\\bé (?:sabido|consenso) que\\b",
      "\\b(?:atua|se configura|se destaca) (?:como|por)\\b",
      "\\bdispõe de\\b",
      "\\b(?:robust[oa]s?|de ponta|de última geração|sem atrito|alavancar\\w*|alavancad[oa]s?|" +
        "alavancando|potencializ\\w+|" +
        "impulsion\\w+|divisor de águas|revolucionári[oa]s?|transformador[ae]?s?|primordial)\\b",
      "\\bnão é só\\b.{0,60}\\bé\\b"
    )
  )

  // PTC-1, the parts a pattern finds: mesoclisis, 3rd-person enclitic, "o mesmo" as a pronoun
  val CLITIC = re(
    "\\b\\w+-(?:se|lo|la|los|las|me|te|nos|vos|lhe|lhes|o|a|os|as)-(?:á|ão|ás|ia|iam|ei|emos|íamos)\\b" +
      "|\\b\\w+[áéêíô]?-(?:o|a|os|as|lo|la|los|las|lhe|lhes)\\b(?!-)" +
      "|\\b(?:o|a|os|as|do|da|dos|das|no|na|nos|nas|ao|à|aos|às|pelo|pela|pelos|pelas)\\s+mesm[oa]s?" +
      "(?=\\s*[.,;:!?)]|\\s+(?:foi|foram|é|são|está|estão|será|serão|tem|têm|deve|devem|pode|podem)\\b)",
    ignoreCase = true
  )
  // "a mesma" after "é" or "sempre" is an adjective (the question is the same), not a pronoun.
  val CLITIC_OK = re(
    "\\b(?:é|são|era|eram|foi|fica|ficam|sempre|continua|continuam)\\s+(?:sempre\\s+)?" +
      "(?:o|a|os|as)\\s+mesm[oa]s?\\b",
    ignoreCase = true
  )

  // PTC-6 at level leve: product and process names are frozen. One spelling for each.
  val FROZEN = List(
    "3Blue1Brown",
    "Manim",
    "Desmos",
    "OpenVoice",
    "MeloTTS",
    "XTTS",
    "Piper",
    "Coqui",
    "MyShell",
    "Lean",
    "Haskell",
    "Z3",
    "Netflix",
    "LinUCB",
    "CMAB",
    "RSI",
    "Claude Code",
    "Anthropic",
    "globo.com",
    "Scala",
    "Python",
    "GitHub",
    "Thompson",
    "A/B"
  )
  val FROZEN_RE =
    FROZEN.map(name => name -> re("(?<![\\w/])" + Pattern.quote(name) + "(?![\\w/])", ignoreCase = true))
  val APOSTROPHE_PLURAL = re("\\b[A-Z]{2,}'s\\b")
  val BR_VARIANT = re("\\b(?:ficheiros?|utilizador(?:es)?|ecrãs?|equipas?|registos?)\\b", ignoreCase = true)

  def frozenHits(prose: String): List[String] =
    val hits = for
      (name, p) <- FROZEN_RE
      m <- Py.findAll(p, prose)
      if m != name && !(name == "Lean" && m == "lean")
    yield m
    hits ++ Py.findAll(APOSTROPHE_PLURAL, prose) ++ Py.findAll(BR_VARIANT, prose)

  def spellingHits(prose: String): List[String] =
    val hits = Py.findAll(SPELLING, prose).filterNot(h => Py.matchStart(SPELLING_OK, h).isDefined)
    val hyphen = Py
      .matches(PREFIX_HYPHEN_VOWEL, prose)
      .filter(m => m.group(1).last.toLower.toString != m.group(2).toLowerCase)
      .map(_.group())
    hits ++ hyphen ++ Py.findAll(TREMA, prose)

  def numberHits(prose: String): List[String] =
    val hits = Py.findAll(NUMBER_FORMAT, prose)
    hits ++ Py
      .matches(DECIMAL_POINT, prose)
      .filterNot(m => Py.search(NUMBER_ID, prose.substring(0, m.start)))
      .map(_.group())

  def cliticHits(prose: String): List[String] =
    val ok = Py.matches(CLITIC_OK, prose).map(_.start)
    Py.matches(CLITIC, prose).filterNot(m => ok.exists(s => s <= m.start && m.start <= s + 20)).map(_.group())

  def pattern(regex: Pattern): String => List[String] = prose => Py.findAll(regex, prose)

  // -------------------------------------------------------------------------------------------
  // The checks Z3 decides

  /** The rule: measure(unit) <= limit, for every unit. `required` at level leve; else recommended. */
  final case class Check(
      rule: String,
      name: String,
      required: Boolean,
      over: String,
      measure: Unit => Int,
      limit: Int,
      explain: Unit => String
  )

  def hitsCheck(rule: String, name: String, required: Boolean, find: String => List[String]): Check =
    Check(
      rule,
      name,
      required,
      "sentence",
      u => find(u.prose).size,
      0,
      u => find(u.prose).distinct.mkString(", ")
    )

  val CHECKS = List(
    Check(
      "PTC-5",
      s"every sentence has at most $MAX_WORDS words",
      true,
      "sentence",
      words,
      MAX_WORDS,
      u => s"${words(u)} words"
    ),
    hitsCheck("PTC-7", "numbers, dates, hours, units and ranges in the Brazilian format", true, numberHits),
    hitsCheck("PTC-8", "spelling of the 1990 Agreement (hyphen, accent, trema)", true, spellingHits),
    hitsCheck("PTC-9", "no chatbot artefact, meta-text or generic conclusion", true, pattern(NOISE_ALWAYS)),
    hitsCheck("PTC-1", "no mesoclisis, 3rd-person enclitic, or 'o mesmo' as a pronoun", true, cliticHits),
    hitsCheck("PTC-6", "product and process names in one spelling; Brazilian variant", true, frozenHits),
    hitsCheck(
      "PTC-9",
      "no filler, vague attribution or inflation (recommended)",
      false,
      pattern(NOISE_FILLER)
    ),
    Check(
      "PTC",
      s"at most $MAX_SENTENCES sentences in a paragraph (recommended)",
      false,
      "paragraph",
      u => u.prose.toInt,
      MAX_SENTENCES,
      u => s"${u.prose} sentences"
    )
  )

  /** Ask Z3 for a unit with measure > limit. Returns (holds, the units of the model). */
  def prove(check: Check, units: List[Unit]): (Boolean, List[Unit]) =
    val solver = ctx.mkSolver()
    val limit = int("limit")
    solver.add(limit === intVal(check.limit))
    val broken = units.zipWithIndex.map { (unit, i) =>
      val x = int(s"${check.rule}[$i]")
      solver.add(x === intVal(check.measure(unit)))
      x > limit
    }
    solver.add(if broken.nonEmpty then or(broken*) else False)
    if solver.check() != Status.SATISFIABLE then (true, Nil)
    else
      val model = solver.getModel
      (false, units.zip(broken).collect { case (u, b) if model.eval(b, false).isTrue => u })

  // -------------------------------------------------------------------------------------------
  // What Z3 cannot decide: the sentences a person reads, for each rule

  val REVIEW: List[(String, String, Option[Pattern])] = List(
    (
      "PTC-1",
      "every finite clause has a lexical subject; no pronoun or demonstrative points " +
        "outside its sentence; no actor is invented (required). Needs a parse and the reference of " +
        "each pronoun. Read the sentences that open with a pronoun or a demonstrative.",
      Some(
        re(
          "^(?:\\W*)(?:Ele|Ela|Eles|Elas|Esse|Essa|Esses|Essas|Isso|Este|Esta|Isto|Aquele" +
            "|Aquela|Aquilo|Nesse|Nessa|Neste|Nesta|Disso|Desse|Dessa)\\b"
        )
      )
    ),
    (
      "PTC-1",
      "no proclitic 3rd-person pronoun ('o calcula', 'a mostra'): 'o' and 'a' are also " +
        "articles, so only a parse tells them apart. Read the sentences with 'o'/'a' before a verb " +
        "form in -a, -e or -am after a noun or 'que'.",
      Some(
        re(
          "\\b(?:que|não|já|se|nunca|também)\\s+(?:o|a|os|as|lhe|lhes)\\s+\\w+(?:a|e|am|em)\\b",
          ignoreCase = true
        )
      )
    ),
    (
      "Level table",
      "a condition or a safety note opens the sentence (required). Needs the scope " +
        "of 'se', 'quando', 'caso', which a pattern cannot fix. Read the sentences where one of them " +
        "is not the first word.",
      Some(
        re(
          "(?<!^)(?<!\\W\\s)(?:,\\s*(?:se|quando|caso)\\s|\\s(?:exceto|a menos que|desde que)\\s)",
          ignoreCase = true
        )
      )
    ),
    (
      "PTC-2",
      "no gerund that joins two clauses (recommended). A gerund after 'estar' is fine; " +
        "only the meaning tells the two apart. Read the sentences with a gerund after a comma.",
      Some(re(",\\s+\\w+ndo\\b", ignoreCase = true))
    ),
    (
      "PTC-3",
      "one meaning per modal; no hedge (recommended, a social hedge is fine). 'deve' is " +
        "obligation or probability, 'pode' is permission or capacity: only the meaning decides. " +
        "Read the sentences with a modal.",
      Some(re("\\b(?:dev[eo]\\w*|deveria\\w*|pode\\w*|poderia\\w*|talvez)\\b", ignoreCase = true))
    ),
    (
      "PTC-5",
      "an adjective goes after its noun (recommended). Needs a part-of-speech tag. Read " +
        "the sentences where an adjective whose meaning changes with its place comes first.",
      Some(
        re(
          "\\b(?:um|uma|o|a|os|as|cada|todo|toda)\\s+(?:simples|cert[oa]s?|únic[oa]s?|nov[oa]s?" +
            "|velh[oa]s?|grandes?|pobres?|antig[oa]s?|bel[oa]s?|pur[oa]s?|mer[oa]s?)\\s+[a-zçãõé]+",
          ignoreCase = true
        )
      )
    ),
    (
      "PTC-6",
      "one concept, one term, in the whole script (required for product and process " +
        "names, checked above; the rest is off at level leve). A synonym for the same concept is " +
        "a matter of meaning: no list can hold all of them.",
      None
    ),
    (
      "PTC-8",
      "spelling outside the curated list (required). The check covers the four hyphen " +
        "cases, the trema, the open diphthong and the differential accents of the PTC reference; " +
        "any other word needs the VOLP of the Academia Brasileira de Letras, which has no API.",
      None
    ),
    (
      "PTC-9",
      "a sentence that says nothing (required for chatbot artefacts, checked above). " +
        "The PTC test is 'what is lost if it goes?', which is a question of meaning.",
      None
    )
  )

  def snippet(raw: String): String = if Py.len(raw) <= 100 then raw else Py.take(raw, 97) + "..."

  def review(sentences: List[Unit]): scala.Unit =
    println("\nRules (or parts of rules) that Z3 cannot decide: read these sentences.")
    for (rule, why, candidates) <- REVIEW do
      println(s"\n$rule: $why")
      for p <- candidates do
        val found = sentences.filter(u => Py.search(p, u.prose))
        for u <- found do println(s"  ${u.file}:${u.line}  ${snippet(u.raw)}")
        println(s"  (${found.size} sentences)")

  // Each required check must reject its BAD text and accept its GOOD text (--self-test). GOOD holds
  // the right forms that look like a break: a scene number, a model version, an ISO month, a hyphen
  // that stays, a name with a trema, "a mesma" as an adjective.
  val SELF_TEST: Map[String, (String, String)] = Map(
    "PTC-5" -> (
      "Esta frase tem " + "muitas " * 33 + "palavras.",
      "Esta frase tem " + "poucas " * 30 + "palavras."
    ),
    "PTC-7" -> (
      "O arquivo tem 1.5 GB, a fila leva 200ms, de 10-20 itens, em 02/08/2026 às 2:30 PM.",
      "A cena 1.4 usa o Claude Sonnet 5.5, 100.000 termos, 0,67, 67 %, 14h30, em 2017-12."
    ),
    "PTC-8" -> (
      "A infra-estrutura usa micro-serviços, um co-autor e a idéia é freqüente.",
      "O anti-inflamatório, o pré-requisito, a infraestrutura, os microsserviços e Müller."
    ),
    "PTC-9" -> ("Ótima pergunta! O futuro é promissor. Espero ter ajudado!", "O serviço reinicia em 5 s."),
    "PTC-1" -> (
      "O pedido chegou. O mesmo foi cancelado. Far-se-á o backup. O laço aprende a enganá-la.",
      "A pergunta é sempre a mesma: a crença nova escolhe a mesma coisa?"
    ),
    "PTC-6" -> ("O manim desenha as API's no ecrã.", "O Manim desenha as APIs na tela.")
  )

  def selfTest(): Int =
    var bad = 0
    for check <- CHECKS if check.required do
      val (reject, accept) = SELF_TEST(check.rule)
      for (text, shouldHold) <- List((reject, false), (accept, true)) do
        val (units, _) = splitSentences(List((1, text)), "self-test")
        val (holds, _) = prove(check, units)
        if holds != shouldHold then
          bad += 1
          println(
            s"FAIL  self-test ${check.rule}: ${if holds then "accepts" else "rejects"} ${Py.repr(text)}"
          )
    println(
      if bad == 0 then "OK    self-test: every required check rejects its bad text and accepts its good text"
      else s"\n$bad self-test failure(s)"
    )
    if bad > 0 then 1 else 0

  def run(args: Seq[String]): Int =
    if args.contains("--self-test") then selfTest() else check(args)

  def check(args: Seq[String]): Int =
    val (sentences, paras) = readScript()
    var failed = 0
    println(
      s"PTC, level $LEVEL: ${sentences.size} sentences and ${paras.size} paragraphs in ${ROOT.relativize(SCRIPT)}/"
    )
    for check <- CHECKS do
      val units = if check.over == "sentence" then sentences else paras
      val (holds, broken) = prove(check, units)
      val status = if holds then "OK  " else if check.required then "FAIL" else "NOTE"
      println(s"$status  ${check.rule}: ${check.name} (${if holds then "unsat" else "sat"})")
      for u <- broken do println(s"        ${u.file}:${u.line}: ${check.explain(u)}")
      if !holds && check.required then failed += 1
    if args.contains("--review") then review(sentences)
    if failed > 0 then
      println(s"\n$failed required PTC check(s) fail")
      1
    else 0
