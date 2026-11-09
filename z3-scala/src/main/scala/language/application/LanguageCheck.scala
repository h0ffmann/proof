// The language rule, run on the files git tracks.
package z3scala.language.application

import kyo.*
import z3scala.kernel.infrastructure.{Failure, Host, Output}
import z3scala.language.domain.LanguageRule

object LanguageCheck:
  def run(using Frame): Int < (Sync & Abort[Failure]) =
    Host
      .runOk(Seq("git", "ls-files"))
      .map: tracked =>
        Kyo
          .foreach(LanguageRule.judged(tracked))(path =>
            Host.readTextIfAny(Host.root.resolve(path)).map(text => (path, text.toOption))
          )
          .map(files => Output.report(LanguageRule.check(files.toList)))
