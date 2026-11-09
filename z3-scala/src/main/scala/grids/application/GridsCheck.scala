// The triangle-grid check, run by the Prover.
package z3scala.grids.application

import kyo.*
import z3scala.grids.domain.Grids
import z3scala.kernel.proof.Prover

object GridsCheck:
  def run(using Frame): Int < Sync = Prover.run(Grids.title, Grids.statements)
