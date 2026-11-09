// The two PTC checks of the video script, run: read the script's Markdown files, give their texts
// to the domain, print its report.
package z3scala.ptc.application

import kyo.*
import z3scala.kernel.infrastructure.{Failure, Host, Output}
import z3scala.ptc.domain.{NoiseCatalogue, Ptc}

object PtcChecks:
  /** The script's Markdown files as (path from the repository root, text), sorted by path. */
  def script(using Frame): List[(String, String)] < (Sync & Abort[Failure]) =
    val dir = Host.root.resolve(Ptc.SCRIPT)
    Host
      .list(dir, _.endsWith(".md"))
      .map: paths =>
        Kyo
          .foreach(paths)(path =>
            Host.readText(path).map(text => (Host.root.relativize(path).toString, text))
          )
          .map(_.toList)

  def ptc(args: Seq[String])(using Frame): Int < (Sync & Abort[Failure]) =
    if args.contains("--self-test") then Output.report(Ptc.selfTest())
    else script.map(files => Output.report(Ptc.check(files, review = args.contains("--review"))))

  def noise(args: Seq[String])(using Frame): Int < (Sync & Abort[Failure]) =
    if args.contains("--self-test") then Output.report(NoiseCatalogue.selfTest())
    else
      NoiseCatalogue.levelArg(args) match
        case Left(message) => Abort.fail(Failure(message, exitCode = 1))
        case Right(level)  =>
          script.map(files =>
            Output.report(NoiseCatalogue.check(files, level, review = args.contains("--review")))
          )
end PtcChecks
