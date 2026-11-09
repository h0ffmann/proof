// z3-scala: the Z3 checks of this repository, in Scala 3.9 (the LTS line). Two dependencies: Z3's
// official Java binding, which Z3 ships inside its release archives, not on Maven (z3.sh puts
// com.microsoft.z3.jar in lib/, sbt's unmanaged jars, and the native libraries in .z3/), and Kyo,
// the effect system the checks run in (README.md, "Layout").
// The settings follow marola-dev/marola-app's build.sbt, with the versions of 2026-11-09.

scalaVersion := "3.9.0"
name := "z3-scala"

// The one dependency, named here although no resolver can fetch it. z3.sh reads this line to
// fetch the release, nix/scala.nix builds the same version, the build stops when the jar is
// missing from lib/, and Main stops when the jar and its native library report another version.
val z3Version = "5.3.3"
val z3Jar = settingKey[File]("Z3's Java binding, put in lib/ by z3.sh")
z3Jar := baseDirectory.value / "lib" / "com.microsoft.z3.jar"
Compile / unmanagedJars := {
  val jar = z3Jar.value
  if !jar.exists then sys.error(s"$jar is missing: run z3-scala/z3.sh, which puts Z3 $z3Version there")
  Seq(Attributed.blank(fileConverter.value.toVirtualFile(jar.toPath)))
}

// Kyo, the effect system: files, processes and the console are Sync and Abort effects, the
// domains are pure. 1.0.0-RC7 is the latest release on Maven Central (read 2026-11-09); it is
// compiled for Java 25, the JDK that nix/scala.nix pins.
val kyoVersion = "1.0.0-RC7"
libraryDependencies += "io.getkyo" %% "kyo-core" % kyoVersion

// The version the jar must report at run time too (Main checks com.microsoft.z3.Version).
Compile / sourceGenerators += Def.task {
  val file = (Compile / sourceManaged).value / "Z3Version.scala"
  IO.write(file, s"package z3scala\n\nval z3Version = \"$z3Version\"\n")
  Seq(file)
}.taskValue

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
  // kernel/smt/Z.scala lets a statement write 0 or 1/2 where Z3 wants a real: the sentence stays readable.
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
Compile / mainClass := Some("z3scala.app.main")

// z3.sh runs the checks with plain `java -cp`, one sbt start per build instead of one per check.
lazy val writeClasspath = taskKey[Unit]("write the runtime classpath, as absolute paths, to target/classpath")
writeClasspath := Def.uncached {
  val converter = fileConverter.value
  val paths = (Runtime / fullClasspath).value.map(a => converter.toPath(a.data).toAbsolutePath.toString)
  IO.write(baseDirectory.value / "target" / "classpath", paths.mkString(java.io.File.pathSeparator))
}
