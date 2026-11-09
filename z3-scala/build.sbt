// z3-scala: the Z3 checks of this repository, in Scala 3.9 (the LTS line). Its one dependency is
// Z3's official Java binding, which Z3 ships inside its release archives, not on Maven: z3.sh
// puts com.microsoft.z3.jar in lib/ (sbt's unmanaged jars) and the native libraries in .z3/.
// The settings follow marola-dev/marola-app's build.sbt, with the versions of 2026-11-09.

scalaVersion := "3.9.0"
name := "z3-scala"

// scalafix's semantic rules (RemoveUnused, OrganizeImports) need SemanticDB.
semanticdbEnabled := true

scalacOptions ++= Seq(
  // Scala 3 syntax only: `if ... then`, `while ... do`, indentation instead of braces.
  "-new-syntax",
  "-Werror",
  "-Wvalue-discard",
  "-Wnonunit-statement",
  "-Wunused:imports,locals,privates,implicits",
  "-language:strictEquality",
  // Z.scala lets a statement write 0 or 1/2 where Z3 wants a real: the sentence stays readable.
  "-language:implicitConversions",
  "-deprecation",
  "-unchecked",
  "-feature"
)

// The checks run in a forked JVM that finds Z3's native libraries in .z3/, from the repository
// z3.sh runs them from the repository root, because every path they read is relative to it.
fork := true
run / javaOptions += s"-Djava.library.path=${baseDirectory.value / ".z3"}"
run / outputStrategy := Some(StdoutOutput)
Compile / mainClass := Some("z3scala.main")

// z3.sh runs the checks with plain `java -cp`, one sbt start per build instead of one per check.
lazy val writeClasspath = taskKey[Unit]("write the runtime classpath, as absolute paths, to target/classpath")
writeClasspath := Def.uncached {
  val converter = fileConverter.value
  val paths = (Runtime / fullClasspath).value.map(a => converter.toPath(a.data).toAbsolutePath.toString)
  IO.write(baseDirectory.value / "target" / "classpath", paths.mkString(java.io.File.pathSeparator))
}
