// The language invariant of the repository, checked with Z3.
//
// The rule (AGENTS.md, "Language", the owner, 2026-11-09): every file is in English, except a
// file whose path carries `pt-BR`, which is in Brazilian Portuguese. As a formula, for every
// tracked text file f:
//
//     portuguese(f)  <->  marked_pt_br(f)
//
// `portuguese(f)` comes from a count of stop words, with fenced code blocks and inline code left
// out (a quoted prompt or a command is not the file's prose): a file is Portuguese when its
// Portuguese stop words are more than twice its English ones (files with fewer than 20 stop words
// of either language are not judged: data, short code, lists). `marked_pt_br(f)` is true when
// `pt-BR` is in the path.
//
// Z3 gets one Boolean per file for each side, fixed to the values measured, and is asked for a
// model of the negation of the rule. "unsat" means that no file breaks it. "sat" gives the files
// that do, from the model.
//
//     z3-scala/z3.sh language   # one line per file that breaks the rule; exit code 1 if any
package z3scala

import com.microsoft.z3.Status

import java.nio.file.{Path, Paths}

import Z.*

object Language:
  val ROOT: Path = Paths.get("").toAbsolutePath

  val PORTUGUESE = Py.re(
    "\\b(de|que|não|para|uma|com|é|os|as|do|da|em|um|são|mais|por|como|se|dos|das|ao|pela|pelo" +
      "|cada|também|mesmo|isso|essa|esse)\\b",
    ignoreCase = true
  )
  val ENGLISH = Py.re(
    "\\b(the|of|and|is|with|that|for|to|in|this|are|from|by|as|it|on|be|or|at|an)\\b",
    ignoreCase = true
  )

  // Not judged: binaries, other people's files, generated HTML, and formats with no prose of ours.
  val SKIPPED = Py.re(
    "\\.(png|jpg|jpeg|gif|webp|pdf|svg|lock|json|html|bib|tex|toml|cabal|csv|tsv|parquet|cff|nix|jsonc)$" +
      "|^(LICENSES|vendor)/"
  )
  val CODE = Py.re("```.*?```|`[^`\\n]*`", dotAll = true)

  val MINIMUM = 20 // stop words of both languages together, below which a file is not judged

  def trackedTextFiles(): List[String] =
    val p = new ProcessBuilder("git", "ls-files").directory(ROOT.toFile).start()
    val out = new String(p.getInputStream.readAllBytes(), "UTF-8")
    if p.waitFor() != 0 then sys.error("git ls-files failed")
    Py.split(out).filterNot(Py.search(SKIPPED, _))

  /** Some(true), Some(false), or None when the file has too few stop words to judge. */
  def isPortuguese(path: String): Option[Boolean] =
    val text =
      try Some(Py.readText(ROOT.resolve(path)))
      catch case _: java.io.IOException => None
    text.flatMap: t =>
      val prose = Py.sub(CODE, " ", t)
      val pt = Py.findAll(PORTUGUESE, prose).size
      val en = Py.findAll(ENGLISH, prose).size
      if pt + en < MINIMUM then None else Some(pt > 2 * en)

  def isMarked(path: String): Boolean = path.contains("pt-BR")

  def run(args: Seq[String]): Int =
    val solver = ctx.mkSolver()
    val broken = List.newBuilder[(String, Bool, Bool)]
    var judged = 0
    for path <- trackedTextFiles(); portuguese <- isPortuguese(path) do
      judged += 1
      val p = bool(s"portuguese[$path]")
      val m = bool(s"marked[$path]")
      solver.add(p === boolVal(portuguese), m === boolVal(isMarked(path)))
      broken += ((path, p, m))
    val all = broken.result()
    val negations = all.map((_, p, m) => xor(p, m)) // the negation of  p <-> m  for each file
    solver.add(or(negations*)) // some file breaks the rule?
    val result = solver.check()
    if result == Status.SATISFIABLE then
      val model = solver.getModel
      var count = 0
      for ((name, p, _), x) <- all.zip(negations) if model.eval(x, false).isTrue do
        count += 1
        println(
          s"FAIL  $name: " + (if model.eval(p, false).isTrue then "Portuguese, but its path has no pt-BR"
                              else "marked pt-BR, but not Portuguese")
        )
      println(s"\n$count file(s) break the language rule")
      1
    else
      println(
        s"OK    $judged files judged: every Portuguese file is marked pt-BR, and only those (${Py.status(result)})"
      )
      0
