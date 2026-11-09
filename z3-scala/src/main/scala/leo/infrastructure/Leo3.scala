// Leo-III as its own process, the way TPTP provers are called: the jar that z3.sh puts in LEO3_JAR.
package z3scala.leo.infrastructure

import kyo.*
import z3scala.kernel.infrastructure.{Failure, Host}

import java.nio.file.Path

object Leo3:
  def jar(using Frame): String < (Sync & Abort[Failure]) =
    Host
      .env("LEO3_JAR")
      .map: found =>
        val path = found.getOrElse("")
        if path.nonEmpty then path
        else Abort.fail(Failure("leo: LEO3_JAR is not set; run it through z3-scala/z3.sh leo"))

  /** What Leo-III prints on the problem, with a time limit in seconds. */
  def prove(jar: String, problem: Path, seconds: Int)(using Frame): String < (Sync & Abort[Failure]) =
    Host.run(Seq("java", "-Xss4m", "-jar", jar, problem.toString, "-t", seconds.toString)).map(_.output)
