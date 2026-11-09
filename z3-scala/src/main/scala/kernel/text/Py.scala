// What the checks need to print and read text exactly as they did when they were Python: Z3's
// values in the Python printer's notation, Python's whitespace and line rules, and its regular
// expressions (Unicode word classes and case folding, which Java turns on by a flag).
package z3scala.kernel.text

import com.microsoft.z3.*
import z3scala.kernel.smt.given

import java.util.regex.{MatchResult, Matcher, Pattern}

object Py:
  /** A Python `re` pattern: str patterns are Unicode-aware there. */
  def re(p: String, ignoreCase: Boolean = false, dotAll: Boolean = false): Pattern =
    var flags = Pattern.UNICODE_CHARACTER_CLASS
    if ignoreCase then flags |= Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE
    if dotAll then flags |= Pattern.DOTALL
    Pattern.compile(p, flags)

  def findAll(p: Pattern, s: String): List[String] =
    val m = p.matcher(s); val b = List.newBuilder[String]
    while m.find() do b += m.group()
    b.result()

  def matches(p: Pattern, s: String): List[MatchResult] =
    val m = p.matcher(s); val b = List.newBuilder[MatchResult]
    while m.find() do b += m.toMatchResult
    b.result()

  def search(p: Pattern, s: String): Boolean = p.matcher(s).find()
  def matchStart(p: Pattern, s: String): Option[Matcher] =
    val m = p.matcher(s); if m.lookingAt() then Some(m) else None
  def sub(p: Pattern, repl: String, s: String): String = p.matcher(s).replaceAll(repl)

  /** Python's str.isspace: Unicode whitespace, the no-break spaces included. */
  def isSpace(c: Int): Boolean =
    Character.isWhitespace(c) || Character.isSpaceChar(c) || (c >= 0x1c && c <= 0x1f) || c == 0x85

  def strip(s: String): String = lstrip(rstrip(s))
  def lstrip(s: String): String =
    var i = 0
    while i < s.length && isSpace(s.codePointAt(i)) do i += Character.charCount(s.codePointAt(i))
    s.substring(i)
  def rstrip(s: String): String =
    var j = s.length
    while j > 0 && isSpace(s.codePointBefore(j)) do j -= Character.charCount(s.codePointBefore(j))
    s.substring(0, j)
  def strip(s: String, chars: String): String =
    var i = 0; var j = s.length
    while i < j && chars.indexOf(s.charAt(i)) >= 0 do i += 1
    while j > i && chars.indexOf(s.charAt(j - 1)) >= 0 do j -= 1
    s.substring(i, j)
  def lstrip(s: String, chars: String): String =
    var i = 0
    while i < s.length && chars.indexOf(s.charAt(i)) >= 0 do i += 1
    s.substring(i)

  /** str.split() with no argument: runs of whitespace, no empty strings. */
  def split(s: String): List[String] =
    val b = List.newBuilder[String]
    val cur = new java.lang.StringBuilder
    var i = 0
    while i < s.length do
      val c = s.codePointAt(i)
      if !isSpace(c) then cur.appendCodePoint(c): Unit
      else if cur.length > 0 then
        b += cur.toString
        cur.setLength(0)
      i += Character.charCount(c)
    if cur.length > 0 then b += cur.toString
    b.result()

  private val lineBreak = Pattern.compile("\r\n|[\n\r\u000b\u000c\u001c\u001d\u001e\u0085  ]")

  /** str.splitlines(). */
  def splitlines(s: String): List[String] =
    if s.isEmpty then Nil
    else
      val parts = lineBreak.split(s, -1).toList
      if lineBreak.matcher(s).find() && parts.last.isEmpty then parts.init else parts

  /** Path.read_text(): universal newlines. */
  /** A file's bytes as Python's text mode reads them: UTF-8, universal newlines. */
  def decode(bytes: Array[Byte], replace: Boolean = false): String =
    val action = if replace then java.nio.charset.CodingErrorAction.REPLACE
    else java.nio.charset.CodingErrorAction.REPORT
    val dec = java.nio.charset.StandardCharsets.UTF_8
      .newDecoder()
      .onMalformedInput(action)
      .onUnmappableCharacter(action)
    dec.decode(java.nio.ByteBuffer.wrap(bytes)).toString.replace("\r\n", "\n").replace("\r", "\n")

  def len(s: String): Int = s.codePointCount(0, s.length)
  def take(s: String, n: Int): String = s.substring(0, s.offsetByCodePoints(0, n min len(s)))
  def ljust(s: String, w: Int): String = s + " " * (w - len(s)).max(0)

  /** f"{n:,}". */
  def thousands(n: Long): String = f"$n%,d".replace(' ', ',').replace('.', ',')

  /** f"{x:.0f}" of a float: the exact binary value, ties to even. */
  def round0(x: Double): String =
    new java.math.BigDecimal(x).setScale(0, java.math.RoundingMode.HALF_EVEN).toPlainString

  /** repr() of a str, for the self-test failures. */
  def repr(s: String): String =
    if s.contains("'") && !s.contains("\"") then "\"" + s + "\""
    else "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"

  // ------------------------------------------------------------------------------------------
  // Z3 values as z3py prints them

  def status(s: Status): String = s match
    case Status.SATISFIABLE   => "sat"
    case Status.UNSATISFIABLE => "unsat"
    case _                    => "unknown"

  def expr(e: Expr[?]): String = e match
    case b: BoolExpr if b.isTrue  => "True"
    case b: BoolExpr if b.isFalse => "False"
    case q: RatNum                =>
      val (n, d) = (q.getBigIntNumerator, q.getBigIntDenominator)
      if d == java.math.BigInteger.ONE then n.toString else s"$n/$d"
    case i: IntNum       => i.getBigInteger.toString
    case v: BitVecNum    => v.getBigInteger.toString
    case a: AlgebraicNum => a.toDecimal(10)
    case f: FPNum        =>
      if f.isNaN then "NaN"
      else if f.isInf then if f.isNegative then "-oo" else "+oo"
      else if f.isZero then if f.isNegative then "-0.0" else "+0.0"
      else
        val exp = f.getExponent(false)
        (if f.getSign then "-" else "") + f.getSignificand + (if exp != "0" then s"*(2**$exp)" else "")
    case other => other.toString

  private def interp(fi: FuncInterp[?]): String =
    val entries = fi.getEntries.toList.map { e =>
      val args = e.getArgs.toList.map(expr)
      (if args.size == 1 then args.head else args.mkString("(", ", ", ")")) + " -> " + expr(e.getValue)
    }
    (entries :+ s"else -> ${expr(fi.getElse)}").mkString("[", ", ", "]")

  def model(m: Model): String =
    val consts = m.getConstDecls.toList.map(d => s"${d.getName} = ${expr(m.getConstInterp(d))}")
    val funcs = m.getFuncDecls.toList.map(d => s"${d.getName} = ${interp(m.getFuncInterp(d))}")
    val entries = consts ++ funcs
    // z3py's printer keeps a model on one line when it fits in 60 columns, else one entry a line.
    val flat = entries.mkString("[", ", ", "]")
    if len(flat) <= 60 then flat else entries.mkString("[", ",\n ", "]")
