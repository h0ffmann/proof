// The Leo-III check: each problem of z3-scala/leo/, proved by Leo-III, judged against its
// expectation (leo/domain/Problem.scala).
//
//     z3-scala/z3.sh leo [seconds]
package z3scala.leo.application

import kyo.*
import z3scala.kernel.infrastructure.{Failure, Host}
import z3scala.kernel.proof.Prover
import z3scala.leo.domain.Problem
import z3scala.leo.infrastructure.Leo3

object LeoCheck:
  def run(args: Seq[String])(using Frame): Int < (Sync & Abort[Failure]) =
    val seconds = args.headOption.flatMap(_.toIntOption).getOrElse(10)
    for
      jar <- Leo3.jar
      files <- Host.list(Host.root.resolve("z3-scala/leo"), _.endsWith(".p"))
      items <- Kyo.foreach(files): file =>
        Host
          .readText(file)
          .map: text =>
            Problem.parse(file.getFileName.toString, text) match
              case Problem(name, Some(theorem)) =>
                Leo3.prove(jar, file, seconds).map(out => Problem.verdict(name, theorem, Problem.status(out)))
              case Problem(name, None) => Problem.unreadable(name)
      code <- Prover.run("leo (Leo-III)", items)
    yield code
