# The z3-scala shell (`nix develop .#scala`; AGENTS.md, "Reproducible builds"): the JDK, sbt, and
# Z3 with its Java binding, with Z3_HOME set, so z3-scala/z3.sh downloads nothing but sbt's Maven
# artifacts. The JDK and Z3 are pinned here; sbt's version is z3-scala/project/build.properties and
# Scala's is z3-scala/build.sbt, both fetched by sbt from Maven Central at those exact versions.
{ pkgs }:
let
  # build.sbt's z3Version, the one place the version is written. A new version also needs the hash
  # of its source below; a stale hash stops the build.
  z3Version = builtins.head (builtins.match ''.*val z3Version = "([^"]+)".*''
    (builtins.readFile ../z3-scala/build.sbt));
  jdk = pkgs.jdk25_headless; # Kyo 1.0 is compiled for Java 25 (class files of version 69)
  sbt = pkgs.sbt.override { jre = jdk; };
  # Z3 with its Java binding, at the version build.sbt names. nixpkgs has an older Z3 (5.1.0), so
  # the source is moved to the release tag; the build, its test run included, is nixpkgs' own.
  z3 = (pkgs.z3.override {
    javaBindings = true;
    pythonBindings = false;
    inherit jdk;
  }).overrideAttrs {
    version = z3Version;
    # nixpkgs' patch for the pkg-config file does not apply to 5.3.3. Its z3.pc.cmake.in joins a
    # prefix with CMAKE_INSTALL_LIBDIR, which Nix makes absolute, so the path gets a '//' and the
    # fixup check fails. The full directories are used instead.
    patches = [ ];
    postPatch = ''
      substituteInPlace z3.pc.cmake.in \
        --replace-fail "\''${exec_prefix}/@CMAKE_INSTALL_LIBDIR@" "@CMAKE_INSTALL_FULL_LIBDIR@" \
        --replace-fail "\''${prefix}/@CMAKE_INSTALL_INCLUDEDIR@" "@CMAKE_INSTALL_FULL_INCLUDEDIR@"
    '';
    src = pkgs.fetchFromGitHub {
      owner = "Z3Prover";
      repo = "z3";
      rev = "z3-${z3Version}";
      hash = "sha256-ScoCwTMULHhh+xurUzmad4PmdaaPbxT3uqR47t4V+5c=";
    };
  };
  # The jar, libz3java and libz3 in one folder: what z3-scala/z3.sh takes as Z3_HOME.
  z3Home = pkgs.symlinkJoin {
    name = "z3-java-${z3.version}";
    paths = [ z3.java z3.lib ];
  };
in
pkgs.mkShell {
  packages = [ jdk sbt pkgs.just pkgs.git ];
  JAVA_HOME = jdk.home;
  Z3_HOME = z3Home;
  passthru = { inherit jdk sbt z3Home; };
}
