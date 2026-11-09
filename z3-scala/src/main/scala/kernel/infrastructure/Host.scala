// The world outside the checks: files, directories and processes, as Kyo effects. Every bounded
// context reaches the disk and the programs it runs (git, java) through here, and a failure is an
// Abort[Failure] that the command line reports, never an exception in a domain.
package z3scala.kernel.infrastructure

import kyo.*
import z3scala.kernel.text.Py

import java.io.IOException
import java.nio.file.{Files, Path, Paths}
import scala.jdk.CollectionConverters.*

/** Why a check could not run: the message for standard error and the exit code. */
final case class Failure(message: String, exitCode: Int = 2)

object Host:
  /** The repository root: every check runs from it (z3.sh changes to it). */
  val root: Path = Paths.get("").toAbsolutePath

  private def io[A](what: => String)(body: => A)(using Frame): A < (Sync & Abort[Failure]) =
    Abort.catching[IOException](e => Failure(s"$what: ${e.getMessage}"))(Sync.defer(body))

  /** A text file, read as Python's text mode reads it (UTF-8, universal newlines). */
  def readText(path: Path, replace: Boolean = false)(using Frame): String < (Sync & Abort[Failure]) =
    io(s"cannot read $path")(Py.decode(Files.readAllBytes(path), replace))

  /** The same, or Absent when the file cannot be read as UTF-8 (a binary, a missing file). */
  def readTextIfAny(path: Path)(using Frame): Maybe[String] < Sync =
    Abort.run[Failure](readText(path)).map(_.toMaybe)

  def writeText(path: Path, text: String)(using Frame): Unit < (Sync & Abort[Failure]) =
    io(s"cannot write $path")(Files.writeString(path, text): Unit)

  def exists(path: Path)(using Frame): Boolean < Sync = Sync.defer(Files.exists(path))

  def createDirectories(path: Path)(using Frame): Unit < (Sync & Abort[Failure]) =
    io(s"cannot create $path")(Files.createDirectories(path): Unit)

  /** The files of a directory whose name passes the filter, sorted by path. */
  def list(dir: Path, keep: String => Boolean)(using Frame): List[Path] < (Sync & Abort[Failure]) =
    io(s"cannot list $dir"):
      val stream = Files.list(dir)
      try stream.iterator.asScala.filter(p => keep(p.getFileName.toString)).toList.sortBy(_.toString)
      finally stream.close()

  /** What a process printed (standard output and error together), and its exit code. */
  final case class Ran(output: String, exitCode: Int)

  def run(command: Seq[String], in: Path = root)(using Frame): Ran < (Sync & Abort[Failure]) =
    io(s"cannot run ${command.headOption.getOrElse("")}"):
      val process = new ProcessBuilder(command*).directory(in.toFile).redirectErrorStream(true).start()
      val out = new String(process.getInputStream.readAllBytes(), "UTF-8")
      Ran(out, process.waitFor())

  /** The same, and a Failure when the process exits with another code than 0. */
  def runOk(command: Seq[String], in: Path = root)(using Frame): String < (Sync & Abort[Failure]) =
    run(command, in).map: ran =>
      if ran.exitCode == 0 then ran.output
      else Abort.fail(Failure(s"${command.mkString(" ")} failed:\n${ran.output}"))

  def env(name: String)(using Frame): Maybe[String] < Sync = Sync.defer(Maybe.fromOption(sys.env.get(name)))

  def printLines(lines: Seq[String])(using Frame): Unit < Sync =
    Kyo.foreachDiscard(lines)(Console.printLine(_))

  def printError(text: String)(using Frame): Unit < Sync = Console.printLineErr(text)
end Host

object Output:
  /** Prints a report's lines and gives its exit code. */
  def report(r: z3scala.kernel.proof.Report)(using Frame): Int < Sync =
    Host.printLines(r.lines).andThen(r.exitCode)

  def print(text: String)(using Frame): Unit < Sync = Console.print(text)
