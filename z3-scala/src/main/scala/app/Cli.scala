// The command line: which check a word names, and what a failure prints. Every check is a Kyo
// computation that gives its exit code; a Failure goes to standard error with its own code.
package z3scala.app

import kyo.*
import z3scala.bandit.application.BanditChecks
import z3scala.grids.application.GridsCheck
import z3scala.kernel.infrastructure.{Failure, Host}
import z3scala.language.application.LanguageCheck
import z3scala.leo.application.LeoCheck
import z3scala.portaudit.application.PortAudit
import z3scala.ptc.application.PtcChecks

object Cli:
  type Command = Seq[String] => Int < (Sync & Abort[Failure])

  val checks: Map[String, Command] = Map(
    "theorems" -> (_ => BanditChecks.theorems),
    "examples" -> (_ => BanditChecks.examples),
    "video" -> (_ => BanditChecks.video),
    "language" -> (_ => LanguageCheck.run),
    "ptc" -> PtcChecks.ptc,
    "ruido-ia" -> PtcChecks.noise,
    "chaceon" -> (_ => PortAudit.chaceon),
    "coverage" -> PortAudit.coverage,
    "grids" -> (_ => GridsCheck.run),
    "leo" -> LeoCheck.run
  )

  val usage: String =
    s"usage: z3-scala/z3.sh <check> [options]; checks: ${checks.keys.toList.sorted.mkString(", ")}"

  def run(args: Seq[String])(using Frame): Int < Sync =
    args.headOption.flatMap(checks.get) match
      case None          => Host.printError(usage).andThen(64)
      case Some(command) =>
        Abort
          .run[Failure](command(args.tail))
          .map:
            case Result.Success(code) => code
            case Result.Failure(f)    => Host.printError(f.message).andThen(f.exitCode)
            case Result.Panic(e)      => throw e
end Cli
