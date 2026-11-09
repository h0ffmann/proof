// `sbt scalafmtCheckAll` and `sbt "scalafixAll --check"`: the format and the lint of z3-scala/README.md.
addSbtPlugin("org.scalameta" % "sbt-scalafmt" % "2.6.2")
addSbtPlugin("ch.epfl.scala" % "sbt-scalafix" % "0.14.10")
