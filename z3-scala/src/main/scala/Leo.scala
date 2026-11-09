// Higher-order statements, proved by Leo-III, an automated prover for classical higher-order logic
// with Henkin semantics and choice (Steen and Benzmüller, "Extensional Higher-Order Paramodulation in
// Leo-III", Journal of Automated Reasoning 65, 2021, arXiv:1907.11501; doi:10.5281/zenodo.4435994).
//
// Z3 decides first-order theories; a statement that quantifies over functions or sets, such as
// Cantor's theorem, is outside them. Each problem is a TPTP THF file in z3-scala/leo/ whose first
// line names the verdict expected of it: `% Expected: Theorem`, or `% Expected: not Theorem` for a
// false statement, which Leo-III must not prove (it answers Timeout or GaveUp, since it builds
// no countermodel). Leo-III runs as its own process, the way TPTP provers are called, and its SZS
// status line is the verdict.
//
//     z3-scala/z3.sh leo [seconds]
package z3scala

import java.nio.file.{Files, Path, Paths}
import scala.jdk.CollectionConverters.*

object Leo:
  private val Status = Py.re("""% SZS status (\w+)""")
  private val Expected = Py.re("""^% Expected: (not )?Theorem""")

  private def prove(jar: String, problem: Path, seconds: Int): String =
    val process = ProcessBuilder("java", "-Xss4m", "-jar", jar, problem.toString, "-t", seconds.toString)
      .redirectErrorStream(true)
      .start()
    val out = String(process.getInputStream.readAllBytes(), "UTF-8")
    val _ = process.waitFor()
    val m = Status.matcher(out)
    if m.find() then m.group(1) else "NoStatus"

  def run(args: Seq[String]): Int =
    val jar = sys.env.getOrElse("LEO3_JAR", "")
    if jar.isEmpty then
      System.err.println("leo: LEO3_JAR is not set; run it through z3-scala/z3.sh leo")
      2
    else
      val seconds = args.headOption.map(_.toInt).getOrElse(10)
      val problems = Files
        .list(Paths.get("z3-scala", "leo"))
        .iterator
        .asScala
        .filter(_.toString.endsWith(".p"))
        .toList
        .sortBy(_.getFileName.toString)
      for problem <- problems do
        val name = problem.getFileName.toString.stripSuffix(".p")
        val firstLine = Py.splitlines(Py.readText(problem)).headOption.getOrElse("")
        val m = Expected.matcher(firstLine)
        if !m.find() then Z.report(name, false, "no `% Expected:` line")
        else
          val theorem = Option(m.group(1)).isEmpty
          val status = prove(jar, problem, seconds)
          val holds = if theorem then status == "Theorem" else status != "Theorem"
          Z.report(
            name,
            holds,
            s"SZS $status${if theorem then "" else " (not a theorem: must not be proved)"}"
          )
      Z.finish("leo (Leo-III)")
