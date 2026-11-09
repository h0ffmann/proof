// One entry point for every check: `z3-scala/z3.sh <check> [options]`.
//
// Not a KyoApp: the checks have their own exit codes (0, 1, 2, 64), and a KyoApp exits with 1 on
// any error. The Kyo computation runs once, here, at the edge of the program.
package z3scala.app

import kyo.*
import z3scala.z3Version

@main def main(args: String*): Unit =
  // The Z3 that build.sbt names, or nothing: a verdict is only as good as the solver that gave it.
  val loaded = com.microsoft.z3.Version.getString
  if !loaded.startsWith(z3Version + ".") then
    System.err.println(s"z3-scala: Z3 $loaded is loaded; build.sbt asks for $z3Version (run z3-scala/z3.sh)")
    sys.exit(2)
  import AllowUnsafe.embrace.danger
  val code = Sync.Unsafe.evalOrThrow(Cli.run(args))
  System.out.flush()
  sys.exit(code)
