// How much of WAVEWATCH III chaceon translated, and how much of that its switches build, with Z3.
//
// Two numbers, both in Fortran code lines of `model/src/*.F90` at chaceon's WW3 pin (lines that are
// not blank, not a `!` comment and not a preprocessor line, the unit of chaceon's
// `scripts/port_summary.py`):
//
// * Translated: the lines of the routines that `rust/ports.tsv` lists, a row being a routine with
//   Rust. Each row's status is its evidence, weakest first: `translated`, `routine`, `host`, `spirv`.
// * Integrated: the translated lines that a chaceon switch file compiles in. WW3 picks its physics
//   and its I/O with `#ifdef W3_<SWITCH>` blocks; a switch file (`switches/switch_chaceon_shrd`, the
//   port's target, and one file per capture build) lists the switches that are on.
//
// Z3 decides the switches. A line's condition is the formula, over one Boolean per `W3_` macro, of
// its file being built (WW3's CMake rules: `switches.json`, `src_list.cmake`, `CMakeLists.txt`) and
// of its preprocessor blocks (`#ifdef`, `#ifndef`, `#if defined ... && ... || !...`, `#elif`,
// `#else`, nested). A switch file compiles the line when the switch set implies the condition: Z3
// finds no counterexample (`unsat`). A line is dead when no switch set that `check_switches.cmake`
// accepts compiles it. Macros that are not switches (`TEST_*`, `ENABLE_*`, `COAMPS`, `NOCGTABLE`...)
// are off, as in a WW3 build with no `-D` flag.
//
//     z3-scala/z3.sh coverage           # fetch the pins into port-audit/.cache, print the tables
//     z3-scala/z3.sh coverage --write   # also write them into port-audit/README.md
//     z3-scala/z3.sh coverage --check   # exit 1 when README.md is stale
//     z3-scala/z3.sh coverage --chaceon DIR --ww3 DIR   # use checkouts already on disk
package z3scala.portaudit

import com.microsoft.z3.{Expr, Status}
import z3scala.Z.*
import z3scala.{Bool, Json, Py, given}

import java.nio.file.{Files, Path, Paths}
import scala.collection.mutable
import scala.jdk.CollectionConverters.*

object Coverage:
  val ROOT: Path = Paths.get("").toAbsolutePath
  val HERE: Path = ROOT.resolve("port-audit")
  val CACHE: Path = HERE.resolve(".cache")
  val README: Path = HERE.resolve("README.md")
  val BEGIN = "<!-- coverage:begin -->"
  val END = "<!-- coverage:end -->"

  val CHACEON_URL = "https://github.com/h0ffmann/chaceon"
  val CHACEON_COMMIT = "fe531e1e64950c0f3ce7987ae4ed0325a56adfbe" // the same pin as Chaceon.scala
  val WW3_URL = "https://github.com/metocean/WW3"
  val WW3_COMMIT = "92e2cf66af6e15ae80eb12562f2b05d4a2d75df5" // chaceon's WW3 submodule at CHACEON_COMMIT

  val TARGET = "switch_chaceon_shrd"
  val EVIDENCE = List("translated", "routine", "host", "spirv") // weakest first, as in rust/ports.tsv

  // ------------------------------------------------------------------------------------------
  // The pins

  private def git(dir: Path, args: String*): (Int, String) =
    val p = new ProcessBuilder(("git" +: "-C" +: dir.toString +: args)*).redirectErrorStream(true).start()
    val out = new String(p.getInputStream.readAllBytes(), "UTF-8")
    (p.waitFor(), out)

  /** A shallow checkout of one commit, only the paths in `sparse`. Reused when it is at the commit. */
  def fetch(url: String, commit: String, into: Path, sparse: List[String]): Path =
    val fresh = !Files.exists(into.resolve(".git"))
    if !fresh && Py.strip(git(into, "rev-parse", "HEAD")._2) == commit then into
    else
      Files.createDirectories(into)
      def run(args: String*): Unit =
        val (code, out) = git(into, args*)
        if code != 0 then sys.error(s"git ${args.mkString(" ")} failed in $into:\n$out")
      if fresh then
        run("init", "-q")
        run("remote", "add", "origin", url)
      run(("sparse-checkout" +: "set" +: "--no-cone" +: sparse)*)
      run("fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", commit)
      run("checkout", "-q", "FETCH_HEAD")
      into

  // ------------------------------------------------------------------------------------------
  // The preprocessor, as Z3 formulas

  val MACRO = Py.re("[A-Za-z_]\\w*")
  val TOKEN = Py.re("defined\\s*\\(\\s*\\w+\\s*\\)|defined\\s+\\w+|&&|\\|\\||!|\\(|\\)|\\w+")

  def macroB(name: String): Bool = bool(name)

  /**
   * The expression of `#if` or `#elif` as a Z3 formula. `defined X`, `defined(X)`, `!`, `&&`, `||`,
   * parentheses. A bare name is defined-ness too: WW3's switches are defined to nothing.
   */
  def condition(text: String): Bool =
    val tokens = Py.findAll(TOKEN, text).toVector
    var pos = 0
    def peek: Option[String] = tokens.lift(pos)
    def take(): String =
      pos += 1
      tokens(pos - 1)
    def primary(): Bool =
      val t = take()
      if t == "!" then not(primary())
      else if t == "(" then
        val e = disjunction()
        if take() != ")" then sys.error(text)
        e
      else if t.startsWith("defined") then macroB(Py.findAll(MACRO, t)(1))
      else if t.forall(Character.isDigit) then boolVal(BigInt(t) != 0)
      else macroB(t)
    def conjunction(): Bool =
      var e = primary()
      while peek.contains("&&") do
        take(): Unit
        e = and(e, primary())
      e
    def disjunction(): Bool =
      var e = conjunction()
      while peek.contains("||") do
        take(): Unit
        e = or(e, conjunction())
      e
    val e = disjunction()
    if pos != tokens.size then sys.error(s"cannot read #if ${Py.repr(text)}")
    e

  val DIRECTIVE = Py.re("^\\s*#\\s*(\\w+)\\s*(.*?)\\s*$")

  def directive(line: String): Option[(String, String)] =
    Py.matchStart(DIRECTIVE, line).map(m => (m.group(1), m.group(2)))

  /** For each line, the formula under which the preprocessor keeps it (None for a directive line). */
  def guards(lines: List[String]): List[Option[Bool]] =
    // stack of (guard of the enclosing block, condition of this branch, any earlier branch)
    val stack = mutable.Stack.empty[(Bool, Bool, Bool)]
    var current: Bool = True
    val out = lines.map: line =>
      val d = directive(line)
      d match
        case Some((kind @ ("if" | "ifdef" | "ifndef"), arg)) =>
          val c0 = if kind == "if" then condition(arg) else macroB(Py.split(arg).head)
          val c = if kind == "ifndef" then not(c0) else c0
          stack.push((current, c, c))
          current = and(current, c)
        case Some(("elif", arg)) =>
          val (outer, _, earlier) = stack.pop()
          val c = and(not(earlier), condition(arg))
          stack.push((outer, c, or(earlier, c)))
          current = and(outer, c)
        case Some(("else", _)) =>
          val (outer, _, earlier) = stack.pop()
          stack.push((outer, not(earlier), True))
          current = and(outer, not(earlier))
        case Some(("endif", _)) =>
          current = stack.pop()._1
        case _ => ()
      if d.isDefined then None else Some(current)
    if stack.nonEmpty then sys.error("unbalanced #if")
    out

  def isCode(line: String): Boolean =
    val s = Py.strip(line)
    s.nonEmpty && !s.startsWith("!") && !s.startsWith("#")

  // ------------------------------------------------------------------------------------------
  // WW3's build rules, as Z3 constraints (model/src/cmake/: switches.json, check_switches.cmake,
  // src_list.cmake, and the program lists of model/src/CMakeLists.txt)

  // Executables CMakeLists.txt always builds, and those it builds when NetCDF is found (chaceon has it).
  val PROGRAMS = List(
    "ww3_strt",
    "ww3_grid",
    "ww3_bound",
    "ww3_outf",
    "ww3_outp",
    "ww3_trck",
    "ww3_grib",
    "ww3_gint",
    "gx_outf",
    "gx_outp",
    "ww3_uprstr",
    "ww3_shel",
    "ww3_prep",
    "ww3_gspl",
    "ww3_multi",
    "ww3_systrk",
    "ww3_ounf",
    "ww3_ounp",
    "ww3_bounc",
    "ww3_trnc",
    "ww3_prnc"
  )

  def switch(name: String): Bool = macroB(s"W3_$name")

  /**
   * The build of one switch set. `valid` is check_switches.cmake: per category of switches.json, "one" means
   * exactly one option, "upto1" at most one, "upto2" at most two; an option's `conflicts` must be off; each
   * string of `requires` must be on, and of an array inside it, one. `built(f)` is the condition under which
   * CMake compiles the file f of model/src.
   */
  final class Rules(ww3: Path):
    private val cmake = ww3.resolve("model/src/cmake")
    private def list(v: Any): List[Any] = v match
      case l: List[?] => l
      case _          => Nil
    private def field(o: Any, k: String): Any = o match
      case m: Map[?, ?] => m.asInstanceOf[Map[String, Any]].getOrElse(k, Nil)
      case _            => Nil
    private val cats = list(Json.parse(Py.readText(cmake.resolve("switches.json"))))
    val options: List[String] =
      cats.flatMap(c => list(field(c, "valid-options")).map(o => field(o, "name").toString)).distinct.sorted
    private val validParts = List.newBuilder[Bool]
    private val builtBy = mutable.LinkedHashMap.empty[String, List[Bool]]
    for c <- cats do
      val opts = list(field(c, "valid-options"))
      val on = opts.map(o => switch(field(o, "name").toString))
      val count = sum(on.map(v => ite(v, intVal(1), intVal(0))))
      validParts += (field(c, "num_switches").toString match
        case "one"   => count === intVal(1)
        case "upto1" => count <= intVal(1)
        case "upto2" => count <= intVal(2)
        case other   => sys.error(s"num_switches $other"))
      for o <- opts do
        val me = switch(field(o, "name").toString)
        for x <- list(field(o, "conflicts")) do validParts += implies(me, not(switch(x.toString)))
        for r <- list(field(o, "requires")) do
          val need = r match
            case alternatives: List[?] => or(alternatives.map(y => switch(y.toString))*)
            case one                   => switch(one.toString)
          validParts += implies(me, need)
        for f <- list(field(o, "build_files")) do
          builtBy(f.toString) = builtBy.getOrElse(f.toString, Nil) :+ me
    val valid: Bool = and(validParts.result()*)
    private val core = Py.split(
      Py.re("set\\(ftn_src(.*?)\\)", dotAll = true)
        .matcher(Py.readText(cmake.resolve("src_list.cmake")))
        .results()
        .findFirst()
        .get()
        .group(1)
    )
    private val pdlib = and(switch("PDLIB"), or(switch("SCOTCH"), switch("METIS")))
    private val table = mutable.Map.empty[String, Bool]
    for (f, conds) <- builtBy do table(f) = or(conds*)
    for f <- core ++ PROGRAMS.map(_ + ".F90") do table(f) = True
    table("ww3_prtide.F90") = switch("TIDE")
    table("w3ounfmetamd.F90") = True // NetCDF found, as in chaceon's build
    for f <- List("pdlib_field_vec.F90", "w3profsmd_pdlib.F90") do table(f) = or(built(f), pdlib)
    def built(f: String): Bool = table.getOrElse(f, False)

  def switchFile(path: Path): Set[String] = Py.split(Py.readText(path)).toSet

  /**
   * Decides, by refutation, which builds keep a line. A switch file fixes every `W3_` macro (on when listed)
   * and leaves every other macro off: `kept(cond, on)` is the theorem "this switch set implies cond".
   * `dead(cond)` asks for a switch set that WW3's rules accept and that keeps the line: `unsat` means none
   * exists.
   */
  final class Builds(rules: Rules, names: Set[String]):
    private val all = (names ++ rules.options.map(o => s"W3_$o")).toList.sorted
    private val cache = mutable.Map.empty[(Int, Any), Boolean]
    private val alive = mutable.ArrayBuffer.empty[Expr[?]] // a Z3 id is reused once its term is freed
    private val off = all.filterNot(_.startsWith("W3_")).map(n => macroB(n) === False)

    def kept(cond: Bool, on: Set[String]): Boolean =
      cache.getOrElseUpdate(
        (cond.getId, on), {
          alive += cond
          val s = ctx.mkSolver()
          for n <- all do s.add(macroB(n) === boolVal(n.startsWith("W3_") && on.contains(n.drop(3))))
          s.add(not(cond))
          val r = s.check()
          if r == Status.UNKNOWN then sys.error(s"unknown: ${s.getReasonUnknown}")
          r == Status.UNSATISFIABLE
        }
      )

    def dead(cond: Bool): Boolean =
      cache.getOrElseUpdate(
        (cond.getId, "dead"), {
          alive += cond
          val s = ctx.mkSolver()
          s.add(rules.valid)
          off.foreach(s.add(_))
          s.add(cond)
          s.check() == Status.UNSATISFIABLE
        }
      )

    /** The rules a switch file breaks, by name of the rule (empty: CMake accepts it). */
    def valid(on: Set[String]): List[String] =
      val s = ctx.mkSolver()
      for o <- rules.options do s.add(switch(o) === boolVal(on.contains(o)))
      s.add(rules.valid)
      if s.check() == Status.SATISFIABLE then Nil
      else
        val unknown = on.toList.sorted.filterNot(rules.options.contains)
        if unknown.nonEmpty then unknown else List("switches.json")

  // ------------------------------------------------------------------------------------------
  // The ledger

  val RANGE = Py.re("model/src/([\\w.]+\\.F90)(?::(\\d+)-(\\d+))?")

  /** Rows of rust/ports.tsv as (routine, file, first, last, status); last None means the whole file. */
  def ledger(chaceon: Path): List[(String, String, Int, Option[Int], String)] =
    Py.splitlines(Py.readText(chaceon.resolve("rust/ports.tsv")))
      .filterNot(l => l.startsWith("#") || l.startsWith("routine\t") || Py.strip(l).isEmpty)
      .map: line =>
        val cells = line.split("\t", -1)
        val (routine, where, status) = (cells(0), cells(1), cells(3))
        val m = RANGE.matcher(where)
        if !m.matches() || !EVIDENCE.contains(status) then sys.error(line)
        val (first, last) =
          Option(m.group(2)).fold[(Int, Option[Int])]((1, None))(g => (g.toInt, Some(m.group(3).toInt)))
        (routine, m.group(1), first, last, status)

  // ------------------------------------------------------------------------------------------

  private def pct(a: Long, b: Long): String = if b != 0 then Py.round0(100.0 * a / b) + "%" else "-"
  private def n(x: Long): String = Py.thousands(x)

  def measure(chaceon: Path, ww3: Path): String =
    val src = ww3.resolve("model/src")
    def sortedFiles(dir: Path, ok: String => Boolean): List[Path] =
      Files.list(dir).iterator.asScala.filter(p => ok(p.getFileName.toString)).toList.sortBy(_.toString)
    val files = sortedFiles(src, _.endsWith(".F90")).map(f =>
      f.getFileName.toString -> Py.splitlines(Py.readText(f, replace = true))
    )
    val switches = sortedFiles(chaceon.resolve("switches"), _.startsWith("switch_")).map(p =>
      p.getFileName.toString -> switchFile(p)
    )
    if !switches.exists(_._1 == TARGET) then sys.error(s"no $TARGET")

    val names = (for
      (_, lines) <- files
      line <- lines
      (kind, arg) <- directive(line).toList
      if Set("if", "ifdef", "ifndef", "elif").contains(kind)
      name <- Py.findAll(MACRO, arg)
      if name != "defined"
    yield name).toSet
    val rules = Rules(ww3)
    val builds = Builds(rules, names)
    val fileLines = files.toMap

    // The status of each translated line: the strongest row of the ledger that covers it.
    val status = mutable.Map.empty[(String, Int), String]
    for (_, f, first, last, st) <- ledger(chaceon); i <- first to last.getOrElse(fileLines(f).size) do
      if status.get((f, i)).forall(old => EVIDENCE.indexOf(st) > EVIDENCE.indexOf(old)) then
        status((f, i)) = st

    var (total, translated, dead, deadTranslated) = (0L, 0L, 0L, 0L)
    val inBuild =
      mutable.Map.empty[String, Long].withDefaultValue(0L) // switch file -> code lines it compiles
    val integrated =
      mutable.Map.empty[String, Long].withDefaultValue(0L) // switch file -> translated lines it compiles
    val byStatus = mutable.Map.empty[String, Array[Long]] // status -> [translated, in TARGET, in some file]
    for (f, lines) <- files do
      val built = rules.built(f)
      for ((line, g), i) <- lines.zip(guards(lines)).zipWithIndex if isCode(line) do
        val cond = and(built, g.getOrElse(True))
        total += 1
        val st = status.get((f, i + 1))
        val kept = switches.collect { case (s, on) if builds.kept(cond, on) => s }.toSet
        for s <- kept do
          inBuild(s) += 1
          if st.isDefined then integrated(s) += 1
        val isDead = builds.dead(cond)
        if isDead then dead += 1
        for s <- st do
          translated += 1
          if isDead then deadTranslated += 1
          val row = byStatus.getOrElseUpdate(s, Array(0L, 0L, 0L))
          row(0) += 1
          if kept.contains(TARGET) then row(1) += 1
          if kept.nonEmpty then row(2) += 1

    val (targetLines, targetIntegrated) = (inBuild(TARGET), integrated(TARGET))
    val anyIntegrated = byStatus.values.map(_(2)).sum
    val out = List.newBuilder[String]
    out ++= List(
      s"Generated by `z3-scala/z3.sh coverage --write` from chaceon `${CHACEON_COMMIT.take(8)}` " +
        s"(`rust/ports.tsv`, `switches/`) and WW3 `${WW3_COMMIT.take(8)}` (`model/src/*.F90`, ${files.size} files, " +
        "and its CMake rules). Unit: Fortran code lines.",
      "",
      "| WW3 code lines | Lines | Share |",
      "|---|---:|---:|",
      s"| All of `model/src/*.F90` | ${n(total)} | 100% |",
      s"| **Translated**: in a routine of `rust/ports.tsv` | ${n(translated)} | ${pct(translated, total)} |",
      s"| Compiled by `$TARGET`, the port's target build | ${n(targetLines)} | ${pct(targetLines, total)} |",
      s"| **Integrated**: translated and compiled by `$TARGET` | ${n(targetIntegrated)} | " +
        s"${pct(targetIntegrated, targetLines)} of the target build |",
      s"| Translated, compiled only by a capture switch file | ${n(anyIntegrated - targetIntegrated)} | " +
        s"${pct(anyIntegrated - targetIntegrated, translated)} of translated |",
      s"| Translated, compiled by no chaceon switch file | ${n(translated - anyIntegrated)} | " +
        s"${pct(translated - anyIntegrated, translated)} of translated |",
      s"| Dead: no switch set that WW3's rules accept compiles it (Z3 `unsat`) | ${n(dead)} | ${pct(dead, total)} |",
      "",
      "| Evidence in `rust/ports.tsv` | Translated | Integrated in the target | In some chaceon switch file |",
      "|---|---:|---:|---:|"
    )
    for st <- EVIDENCE.reverse do
      val Array(t, i, a) = byStatus.getOrElse(st, Array(0L, 0L, 0L)): @unchecked
      out += s"| `$st` | ${n(t)} | ${n(i)} | ${n(a)} |"
    out ++= List(
      "",
      "| Switch file | WW3's rules (Z3) | Compiles | Of it translated |",
      "|---|---|---:|---:|"
    )
    for (s, on) <- switches do
      val broken = builds.valid(on)
      val verdict = if broken.isEmpty then "accepted" else "breaks " + broken.map(b => s"`$b`").mkString(", ")
      out += s"| `$s` | $verdict | ${n(inBuild(s))} | ${n(integrated(s))} (${pct(integrated(s), inBuild(s))}) |"
    val unreachable = rules.options.filterNot(possible(rules, _))
    out ++= List(
      "",
      s"Translated lines that are dead: ${n(deadTranslated)}. Switch options that no accepted switch " +
        s"set can turn on: ${
            if unreachable.isEmpty then "none" else unreachable.map(o => s"`$o`").mkString(", ")
          }."
    )
    Py.rstrip(out.result().mkString("\n")) + "\n"

  private def possible(rules: Rules, option: String): Boolean =
    val s = ctx.mkSolver()
    s.add(rules.valid, switch(option))
    s.check() == Status.SATISFIABLE

  def run(args: Seq[String]): Int =
    def opt(flag: String): Option[Path] = args.indexOf(flag) match
      case -1 => None
      case i  => args.lift(i + 1).map(Paths.get(_).toAbsolutePath)
    val (write, check) = (args.contains("--write"), args.contains("--check"))
    if write && check then
      System.err.println("coverage: --write and --check are exclusive")
      2
    else
      val chaceon = opt("--chaceon").getOrElse(
        fetch(CHACEON_URL, CHACEON_COMMIT, CACHE.resolve("chaceon"), List("/rust/ports.tsv", "/switches/"))
      )
      val ww3 = opt("--ww3").getOrElse(fetch(WW3_URL, WW3_COMMIT, CACHE.resolve("WW3"), List("/model/src/")))
      val table = measure(chaceon, ww3)
      print(table)
      System.out.flush()
      val text = Files.readString(README)
      val (head, rest) = text.splitAt(text.indexOf(BEGIN))
      val tail = rest.substring(rest.indexOf(END) + END.length)
      val fresh = s"$head$BEGIN\n\n$table\n$END$tail"
      if write then
        Files.writeString(README, fresh): Unit
        0
      else if check && fresh != text then
        System.err.println("coverage: README.md is stale; run z3-scala/z3.sh coverage --write")
        1
      else 0
