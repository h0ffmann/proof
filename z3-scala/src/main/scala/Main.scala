// One entry point for every check: `z3-scala/z3.sh <check> [options]`.
package z3scala

@main def main(args: String*): Unit =
  // The reports quote Portuguese prose: UTF-8, whatever the locale of the terminal.
  System.setOut(java.io.PrintStream(java.io.FileOutputStream(java.io.FileDescriptor.out), true, "UTF-8"))
  val checks: Map[String, Seq[String] => Int] = Map(
    "theorems" -> Theorems.run,
    "examples" -> Examples.run,
    "video" -> Video.run,
    "language" -> Language.run,
    "ptc" -> Ptc.run,
    "ruido-ia" -> RuidoIa.run,
    "chaceon" -> portaudit.Chaceon.run,
    "coverage" -> portaudit.Coverage.run,
    "grids" -> grids.Grids.run,
    "leo" -> Leo.run
  )
  args.headOption.flatMap(checks.get) match
    case Some(check) => sys.exit(check(args.tail))
    case None        =>
      System.err.println(
        s"usage: z3-scala/z3.sh <check> [options]; checks: ${checks.keys.toList.sorted.mkString(", ")}"
      )
      sys.exit(64)
