#!/usr/bin/env bash
# Run one check of z3-scala, from the repository root:
#
#   z3-scala/z3.sh theorems | examples | video | language | ptc | ruido-ia | chaceon | coverage | grids | leo [options]
#
# Run it inside `nix develop .#scala`, the root flake's shell: it pins the JDK, sbt and Z3 with its
# Java binding, and sets Z3_HOME. The first run puts that binding in place: the jar in
# z3-scala/lib/ and its native libraries in z3-scala/.z3/. They come from Z3_HOME when it is set (a
# directory that holds com.microsoft.z3.jar and libz3java), or else, outside the shell, from the Z3
# release on GitHub for this platform, checked against the SHA-256 that GitHub publishes for the
# asset. The version is build.sbt's z3Version. The classpath is cached in
# z3-scala/target/classpath and rebuilt by sbt when a source or build file is newer.
#
# `leo` also needs Leo-III, a higher-order prover written in Scala that publishes no jar for its
# current version: LEO3_JAR names one, or else the first run builds it with sbt from
# leoprover/Leo-III at LEO3_COMMIT into z3-scala/.leo/.
set -euo pipefail

# The Z3 version is build.sbt's z3Version, the one place it is written.
Z3_VERSION=$(sed -n 's/^val z3Version = "\(.*\)"$/\1/p' "$(dirname "$0")/build.sbt")
LEO3_COMMIT=d24be031e54f5378d0bc441f5bbd112c96214dfa # version 1.8.1, Scala 3.9.0, 26 October 2026
here=$(cd "$(dirname "$0")" && pwd)
[ -n "$Z3_VERSION" ] || { echo "z3-scala: no z3Version in build.sbt" >&2; exit 1; }
root=$(cd "$here/.." && pwd)

die() { echo "z3-scala: $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=osx; ext=dylib ;;
  Linux) os=glibc; ext=so ;;
  *) die "no Z3 release for $(uname -s); set Z3_HOME" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) die "no Z3 release for $(uname -m); set Z3_HOME" ;;
esac

install_from() { # a directory that holds the jar and the native libraries, in any subfolder
  local src=$1 jar lib
  jar=$(find "$src" -name com.microsoft.z3.jar | head -1)
  lib=$(find "$src" -name "libz3java.$ext" | head -1)
  [ -n "$jar" ] && [ -n "$lib" ] || die "$src has no com.microsoft.z3.jar and libz3java.$ext"
  mkdir -p "$here/lib" "$here/.z3"
  cp "$jar" "$here/lib/com.microsoft.z3.jar"
  cp -P "$(dirname "$lib")"/libz3*."$ext"* "$here/.z3/"
}

download() {
  local api asset url digest tmp
  command -v curl > /dev/null || die "curl is needed to fetch Z3 $Z3_VERSION; or set Z3_HOME"
  api=$(curl -fsSL "https://api.github.com/repos/Z3Prover/z3/releases/tags/z3-$Z3_VERSION") \
    || die "cannot read the release z3-$Z3_VERSION from api.github.com; set Z3_HOME"
  # The asset names carry the platform, e.g. z3-5.3.3-arm64-osx-13.3.zip, z3-5.3.3-x64-glibc-2.39.zip.
  asset=$(printf '%s\n' "$api" | grep -o "\"name\": *\"z3-$Z3_VERSION-$arch-$os[^\"]*\.zip\"" | head -1 \
    | sed 's/.*: *"\(.*\)"/\1/')
  [ -n "$asset" ] || die "no asset for $arch-$os in z3-$Z3_VERSION; set Z3_HOME"
  url="https://github.com/Z3Prover/z3/releases/download/z3-$Z3_VERSION/$asset"
  digest=$(printf '%s\n' "$api" | tr -d '\n' | grep -o "\"name\": *\"$asset\"[^}]*\"digest\": *\"sha256:[0-9a-f]*\"" \
    | grep -o 'sha256:[0-9a-f]*' | head -1 | cut -d: -f2 || true)
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  echo "z3-scala: fetching $asset" >&2
  curl -fsSL -o "$tmp/z3.zip" "$url" || die "cannot download $url"
  if [ -n "$digest" ]; then
    local sum
    sum=$( (sha256sum "$tmp/z3.zip" 2> /dev/null || shasum -a 256 "$tmp/z3.zip") | cut -d' ' -f1)
    [ "$sum" = "$digest" ] || die "$asset: SHA-256 $sum, GitHub says $digest"
  else
    echo "z3-scala: GitHub gives no digest for $asset; not checked" >&2
  fi
  (cd "$tmp" && unzip -q z3.zip)
  install_from "$tmp"
}

stamp="$here/.z3/version"
if [ -z "${IN_NIX_SHELL:-}" ]; then
  echo "z3-scala: not in \`nix develop .#scala\`; using the JDK and sbt on PATH, which nothing pins" >&2
fi
if [ ! -f "$here/lib/com.microsoft.z3.jar" ] || [ "$(cat "$stamp" 2> /dev/null)" != "$Z3_VERSION ${Z3_HOME:-release}" ]; then
  if [ -n "${Z3_HOME:-}" ]; then install_from "$Z3_HOME"; else download; fi
  echo "$Z3_VERSION ${Z3_HOME:-release}" > "$stamp"
fi

cp_file="$here/target/classpath"
if [ ! -s "$cp_file" ] || [ -n "$(find "$here/src" "$here/build.sbt" "$here/project" "$here/lib" -newer "$cp_file" -type f 2> /dev/null | head -1)" ]; then
  command -v sbt > /dev/null || die "sbt is needed to build z3-scala"
  mkdir -p "$here/target"
  out=$(cd "$here" && sbt -Dsbt.supershell=false writeClasspath 2>&1) \
    || { printf '%s\n' "$out" >&2; die "sbt failed"; }
  [ -s "$cp_file" ] || { printf '%s\n' "$out" >&2; die "sbt wrote no classpath"; }
fi

leo3() {
  local dir="$here/.leo" jar
  jar="$dir/leo3-$LEO3_COMMIT.jar"
  if [ ! -f "$jar" ]; then
    command -v git > /dev/null || die "git is needed to build Leo-III; or set LEO3_JAR"
    rm -rf "$dir/src" && mkdir -p "$dir/src"
    echo "z3-scala: building Leo-III at ${LEO3_COMMIT:0:8}" >&2
    (cd "$dir/src" && git init -q && git fetch -q --depth 1 https://github.com/leoprover/Leo-III.git "$LEO3_COMMIT" \
      && git checkout -q FETCH_HEAD) || die "cannot fetch Leo-III at $LEO3_COMMIT"
    (cd "$dir/src" && sbt -Dsbt.supershell=false assembly > "$dir/build.log" 2>&1) \
      || die "Leo-III did not build; see $dir/build.log"
    cp "$dir"/src/target/scala-*/leo3-*.jar "$jar"
  fi
  echo "$jar"
}
if [ "${1:-}" = leo ] && [ -z "${LEO3_JAR:-}" ]; then
  LEO3_JAR=$(leo3)
  export LEO3_JAR
fi

cd "$root"
# The reports quote Portuguese prose: UTF-8 on standard output and error, whatever the locale.
exec java --enable-native-access=ALL-UNNAMED -Djava.library.path="$here/.z3" -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 \
  -cp "$(cat "$cp_file")" z3scala.app.main "$@"
