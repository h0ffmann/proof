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
package z3scala.leo.domain

import z3scala.kernel.proof.Item
import z3scala.kernel.text.Py

/** A TPTP problem of z3-scala/leo/, and whether Leo-III must prove it. None: no `% Expected:` line. */
final case class Problem(name: String, theorem: Option[Boolean])

object Problem:
  private val Status = Py.re("""% SZS status (\w+)""")
  private val Expected = Py.re("""^% Expected: (not )?Theorem""")

  def parse(file: String, text: String): Problem =
    val firstLine = Py.splitlines(text).headOption.getOrElse("")
    val m = Expected.matcher(firstLine)
    Problem(file.stripSuffix(".p"), if m.find() then Some(Option(m.group(1)).isEmpty) else None)

  /** The SZS status in Leo-III's output. */
  def status(output: String): String =
    val m = Status.matcher(output)
    if m.find() then m.group(1) else "NoStatus"

  /** The verdict on a problem whose expectation is known, from the SZS status Leo-III gave. */
  def verdict(name: String, theorem: Boolean, status: String): Item =
    val holds = if theorem then status == "Theorem" else status != "Theorem"
    Item.Verdict(name, holds, s"SZS $status${if theorem then "" else " (not a theorem: must not be proved)"}")

  def unreadable(name: String): Item = Item.Verdict(name, false, "no `% Expected:` line")
