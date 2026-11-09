// The contextual-bandit paper's three checks, run by the Prover.
package z3scala.bandit.application

import kyo.*
import z3scala.bandit.domain.{Examples, Theorems, Video}
import z3scala.kernel.proof.Prover

object BanditChecks:
  def theorems(using Frame): Int < Sync = Prover.run(Theorems.title, Theorems.statements)
  def examples(using Frame): Int < Sync = Prover.run(Examples.title, Examples.statements)
  def video(using Frame): Int < Sync = Prover.run(Video.title, Video.statements)
