// A report that is text, not statements: the lines a domain writes, and the exit code it decides.
// The domain builds it without printing; the application prints it through Kyo's Console.
package z3scala.kernel.proof

final case class Report(lines: Vector[String], exitCode: Int)

final class Lines:
  private val lines = Vector.newBuilder[String]
  private[proof] def add(text: String): Unit = lines += text
  private[proof] def result: Vector[String] = lines.result()

object Report:
  /** The lines that `say` writes in the body, and the exit code the body returns. */
  def apply(body: Lines ?=> Int): Report =
    val lines = new Lines
    val code = body(using lines)
    Report(lines.result, code)

  def say(text: String = "")(using l: Lines): Unit = l.add(text)
