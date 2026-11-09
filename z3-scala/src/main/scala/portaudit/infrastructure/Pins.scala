// The two pins the coverage is measured at, on disk: shallow, sparse git checkouts of chaceon and
// of WW3 in port-audit/.cache, and the files the domain reads from them.
package z3scala.portaudit.infrastructure

import kyo.*
import z3scala.kernel.infrastructure.{Failure, Host}
import z3scala.kernel.text.Py
import z3scala.portaudit.domain.Coverage.{CHACEON_COMMIT, CHACEON_URL, WW3_COMMIT, WW3_URL}
import z3scala.portaudit.domain.Sources

import java.nio.file.Path

object Pins:
  val cache: Path = Host.root.resolve("port-audit/.cache")

  private def git(dir: Path, args: String*)(using Frame) = Host.run(Seq("git", "-C", dir.toString) ++ args)

  private def gitOk(dir: Path, args: String*)(using Frame): Unit < (Sync & Abort[Failure]) =
    git(dir, args*).map: ran =>
      if ran.exitCode == 0 then ()
      else Abort.fail(Failure(s"git ${args.mkString(" ")} failed in $dir:\n${ran.output}"))

  /** A shallow checkout of one commit, only the paths in `sparse`. Reused when it is at the commit. */
  def fetch(url: String, commit: String, into: Path, sparse: List[String])(using
      Frame
  ): Path < (Sync & Abort[Failure]) =
    Host
      .exists(into.resolve(".git"))
      .map: present =>
        val head: String < (Sync & Abort[Failure]) =
          if present then git(into, "rev-parse", "HEAD").map(r => Py.strip(r.output)) else ""
        head.map: at =>
          if present && at == commit then into
          else
            for
              _ <- Host.createDirectories(into)
              _ <-
                if present then Kyo.unit
                else gitOk(into, "init", "-q").andThen(gitOk(into, "remote", "add", "origin", url))
              _ <- gitOk(into, ("sparse-checkout" +: "set" +: "--no-cone" +: sparse)*)
              _ <- gitOk(into, "fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", commit)
              _ <- gitOk(into, "checkout", "-q", "FETCH_HEAD")
            yield into

  def chaceon(using Frame): Path < (Sync & Abort[Failure]) =
    fetch(CHACEON_URL, CHACEON_COMMIT, cache.resolve("chaceon"), List("/rust/ports.tsv", "/switches/"))

  def ww3(using Frame): Path < (Sync & Abort[Failure]) =
    fetch(WW3_URL, WW3_COMMIT, cache.resolve("WW3"), List("/model/src/"))

  private def named(dir: Path, keep: String => Boolean, replace: Boolean = false)(using Frame) =
    Host
      .list(dir, keep)
      .map: paths =>
        Kyo
          .foreach(paths)(p => Host.readText(p, replace).map(text => (p.getFileName.toString, text)))
          .map(_.toList)

  /** What Coverage.measure reads, from checkouts of chaceon and WW3. */
  def sources(chaceon: Path, ww3: Path)(using Frame): Sources < (Sync & Abort[Failure]) =
    val src = ww3.resolve("model/src")
    for
      fortran <- named(src, _.endsWith(".F90"), replace = true)
      json <- Host.readText(src.resolve("cmake/switches.json"))
      srcList <- Host.readText(src.resolve("cmake/src_list.cmake"))
      switches <- named(chaceon.resolve("switches"), _.startsWith("switch_"))
      ports <- Host.readText(chaceon.resolve("rust/ports.tsv"))
    yield Sources(fortran.map((name, text) => name -> Py.splitlines(text)), json, srcList, switches, ports)
end Pins
