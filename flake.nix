{
  description = "dogma: the paper toolchain comes from h0ffmann/picasso's paper lab (Paper Fabric)";

  # `nix flake update` picks up a new revision of the lab.
  inputs.paper.url = "github:h0ffmann/picasso?dir=labs/paper";

  outputs = { paper, ... }:
    let
      # One nixpkgs for every shell: the paper lab's, pinned by flake.lock.
      pkgsFor = system: paper.inputs.nixpkgs.legacyPackages.${system};

      # z3-scala's toolchain (AGENTS.md, "Reproducible builds"). The JDK and Z3 are pinned here;
      # sbt's own version is z3-scala/project/build.properties and Scala's is z3-scala/build.sbt,
      # both fetched by sbt from Maven Central at those exact versions.
      # build.sbt's z3Version, the one place the version is written. A new version also needs the
      # hash of its source below; a stale hash stops the build.
      z3Version = builtins.head (builtins.match ''.*val z3Version = "([^"]+)".*''
        (builtins.readFile ./z3-scala/build.sbt));
      scala = pkgs: rec {
        jdk = pkgs.jdk25_headless; # Kyo 1.0 is compiled for Java 25 (class files of version 69)
        sbt = pkgs.sbt.override { jre = jdk; };
        # Z3 with its Java binding, at the version z3-scala/build.sbt names (z3Version). nixpkgs
        # has an older Z3 (5.1.0), so the source is moved to the release tag; the build, its test
        # run included, is nixpkgs' own.
        z3 = (pkgs.z3.override {
          javaBindings = true;
          pythonBindings = false;
          inherit jdk;
        }).overrideAttrs {
          version = z3Version;
          # nixpkgs' patch makes the pkg-config file absolute; 5.3.3's is relative already.
          patches = [ ];
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
      };
    in
    {
      packages = builtins.mapAttrs
        (system: _:
          let s = scala (pkgsFor system); in { z3-java = s.z3Home; inherit (s) jdk sbt; })
        paper.devShells;

      # default: pandoc, pandoc-crossref, XeLaTeX, pdfLaTeX and just (the paper lab), plus Gleam on
      # Erlang for tools/ (refs-check, ste-check). md: the three Markdown analysers of
      # `just md-quality`. scala: the JDK, sbt and Z3 of z3-scala/, with Z3_HOME set, so z3.sh
      # downloads nothing but sbt's Maven artifacts. Everything comes from the paper lab's nixpkgs,
      # so flake.lock pins it all.
      devShells = builtins.mapAttrs
        (system: shells:
          let
            pkgs = pkgsFor system;
            s = scala pkgs;
          in
          {
            default = pkgs.mkShell {
              inputsFrom = [ shells.default ];
              packages = [ pkgs.gleam pkgs.beamPackages.erlang pkgs.beamPackages.rebar3 ];
            };
            md = pkgs.mkShell { packages = [ pkgs.markdownlint-cli2 pkgs.vale pkgs.lychee ]; };
            scala = pkgs.mkShell {
              packages = [ s.jdk s.sbt pkgs.just pkgs.git ];
              JAVA_HOME = s.jdk.home;
              Z3_HOME = s.z3Home;
            };
          })
        paper.devShells;
    };
}
