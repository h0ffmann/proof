// How every check proves a statement: by refutation, and how its report is kept.
//
// A theorem "premises imply conclusion" holds when Z3 finds no model of "premises and not
// conclusion": the answer `unsat`. A model, when there is one, is a counterexample and is printed.
//
// A bounded context states its statements as values (Item), in the order of its report, with the
// vocabulary of Script; the Prover runs them in Kyo: each item is judged inside Sync, its line is
// printed through Console, and the tally lives in a Var. The exit code is 1 when a statement
// failed.
package z3scala.kernel.proof

import com.microsoft.z3.Status
import kyo.*
import z3scala.kernel.smt.Z.*
import z3scala.kernel.smt.{*, given}
import z3scala.kernel.text.Py

/** One line of a report. */
enum Item:
  /** The premises imply the conclusion, for every value of the free symbols. */
  case Proves(name: String, premises: Seq[Bool], conclusion: Bool, note: String)

  /** The closed expression equals the expected rational. */
  case Evaluates(name: String, expression: Real, expected: Rational)

  /** A counterexample is expected: the statement must fail, and the model shows why. */
  case Refutes(name: String, premises: Seq[Bool], conclusion: Bool, why: String)

  /** A verdict reached outside Z3 (another prover, a measurement). */
  case Verdict(name: String, holds: Boolean, note: String)

  /** A line of text: a NOTE, a heading, a blank line. */
  case Line(text: String)
end Item

/** The statements a check has proved so far, and how many failed. */
final case class Tally(checked: Int, failed: Int):
  def add(holds: Boolean): Tally = Tally(checked + 1, if holds then failed else failed + 1)

/** Builds a check's items in order, so that a statement is still written as `proves(...)`. */
final class Script:
  private val items = Vector.newBuilder[Item]
  private[proof] def add(item: Item): Unit = items += item
  private[proof] def result: Vector[Item] = items.result()

object Script:
  def apply(body: Script ?=> Unit): Vector[Item] =
    val script = new Script
    body(using script)
    script.result

  def proves(name: String, premises: Seq[Bool], conclusion: Bool, note: String = "")(using s: Script): Unit =
    s.add(Item.Proves(name, premises, conclusion, note))

  def evaluates(name: String, expression: Real, expected: Rational)(using s: Script): Unit =
    s.add(Item.Evaluates(name, expression, expected))

  def counterexample(name: String, premises: Seq[Bool], conclusion: Bool, why: String)(using
      s: Script
  ): Unit =
    s.add(Item.Refutes(name, premises, conclusion, why))

  def verdict(name: String, holds: Boolean, note: String)(using s: Script): Unit =
    s.add(Item.Verdict(name, holds, note))

  def line(text: String = "")(using s: Script): Unit = s.add(Item.Line(text))
end Script

object Prover:
  /** The line of a statement: OK or FAIL, the name in a column of 34, the note. */
  def format(name: String, holds: Boolean, note: String): String =
    s"${if holds then "OK  " else "FAIL"}  ${Py.ljust(name, 34)} $note"

  /** Runs the items in order, prints a line each and the summary, and gives the exit code. */
  def run(title: String, items: Seq[Item])(using Frame): Int < Sync =
    Var.run(Tally(0, 0)) {
      Kyo.foreachDiscard(items)(step).andThen(summary(title))
    }

  private def step(item: Item)(using Frame): Unit < (Var[Tally] & Sync) = item match
    case Item.Line(text) => Console.printLine(text)
    case statement       =>
      Sync
        .defer(judge(statement))
        .map: (holds, note) =>
          Var
            .updateDiscard[Tally](_.add(holds))
            .andThen(Console.printLine(format(nameOf(statement), holds, note)))

  private def summary(title: String)(using Frame): Int < (Var[Tally] & Sync) =
    Var
      .get[Tally]
      .map: tally =>
        val text =
          if tally.failed > 0 then s"$title: ${tally.failed} of ${tally.checked} failed"
          else s"$title: all ${tally.checked} hold"
        Console.printLine("").andThen(Console.printLine(text)).andThen(if tally.failed > 0 then 1 else 0)

  private def nameOf(item: Item): String = item match
    case Item.Proves(name, _, _, _)  => name
    case Item.Evaluates(name, _, _)  => name
    case Item.Refutes(name, _, _, _) => name
    case Item.Verdict(name, _, _)    => name
    case Item.Line(text)             => text

  /** Whether the item holds, and the note of its line. Z3 is called here. */
  private def judge(item: Item): (Boolean, String) = item match
    case Item.Proves(_, premises, conclusion, note) =>
      val s = ctx.mkSolver()
      premises.foreach(s.add(_))
      s.add(not(conclusion))
      val result = s.check()
      val holds = result == Status.UNSATISFIABLE
      val shown =
        if holds then note
        else
          Py.status(result) +
            (if result == Status.SATISFIABLE then s", counterexample ${Py.model(s.getModel)}" else "")
      (holds, if shown.isEmpty then "no counterexample (unsat)" else shown)
    case Item.Evaluates(_, expression, expected) =>
      val value = expression.simplify()
      val holds = ctx.mkEq(value, num(expected)).simplify().isTrue
      (holds, s"= ${Py.expr(value)}  (expected $expected)")
    case Item.Refutes(_, premises, conclusion, why) =>
      val s = ctx.mkSolver()
      premises.foreach(s.add(_))
      s.add(not(conclusion))
      val found = s.check() == Status.SATISFIABLE
      (
        found,
        if found then s"counterexample ${Py.model(s.getModel)} ($why)"
        else "no counterexample, but one was expected"
      )
    case Item.Verdict(_, holds, note) => (holds, note)
    case Item.Line(text)              => (true, text)
end Prover
