// The two checks of the chaceon port: its arithmetic (Chaceon, statements for the Prover) and its
// coverage of WAVEWATCH III (Coverage, tables measured on the two pins).
package z3scala.portaudit.application

import kyo.*
import z3scala.kernel.infrastructure.{Failure, Host, Output}
import z3scala.kernel.proof.Prover
import z3scala.portaudit.domain.{Chaceon, Coverage}
import z3scala.portaudit.infrastructure.Pins

import java.nio.file.{Path, Paths}

object PortAudit:
  def chaceon(using Frame): Int < Sync = Prover.run(Chaceon.title, Chaceon.statements)

  //     z3-scala/z3.sh coverage [--write | --check] [--chaceon DIR --ww3 DIR]
  def coverage(args: Seq[String])(using Frame): Int < (Sync & Abort[Failure]) =
    def opt(flag: String): Option[Path] = args.indexOf(flag) match
      case -1 => None
      case i  => args.lift(i + 1).map(Paths.get(_).toAbsolutePath)
    val (write, check) = (args.contains("--write"), args.contains("--check"))
    if write && check then Abort.fail(Failure("coverage: --write and --check are exclusive"))
    else
      val readme = Host.root.resolve(Coverage.README)
      for
        chaceon <- opt("--chaceon").fold(Pins.chaceon)(p => p: Path < Sync)
        ww3 <- opt("--ww3").fold(Pins.ww3)(p => p: Path < Sync)
        sources <- Pins.sources(chaceon, ww3)
        table = Coverage.measure(sources)
        _ <- Output.print(table)
        text <- Host.readText(readme)
        fresh = Coverage.splice(text, table)
        code <-
          if write then Host.writeText(readme, fresh).andThen(0)
          else if check && fresh != text then
            Abort.fail(
              Failure("coverage: README.md is stale; run z3-scala/z3.sh coverage --write", exitCode = 1)
            )
          else 0: Int < Sync
      yield code
end PortAudit
