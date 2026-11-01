//// What the scripts needed from Python's os, sys, subprocess, pathlib, tempfile, hashlib, tarfile
//// and urllib, over fabric_ffi.erl. Paths are relative to the repository root unless absolute:
//// the `tools/fabric` wrapper starts the VM there, as `ROOT` was in each script.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string

@external(erlang, "fabric_ffi", "args")
pub fn args() -> List(String)

@external(erlang, "fabric_ffi", "getenv")
pub fn getenv(name: String) -> Result(String, Nil)

/// Ends the program with this exit status, after flushing output.
@external(erlang, "fabric_ffi", "halt")
pub fn exit(code: Int) -> a

@external(erlang, "fabric_ffi", "eprint")
fn eprint(text: String) -> Nil

/// print(..., file=sys.stderr)
pub fn eprintln(text: String) -> Nil {
  eprint(text <> "\n")
}

@external(erlang, "fabric_ffi", "read_file")
fn read_bits(path: String) -> Result(BitArray, String)

pub fn read_bytes(path: String) -> Result(BitArray, String) {
  read_bits(path)
}

/// Path.read_text(); invalid UTF-8 is an error.
pub fn read(path: String) -> Result(String, String) {
  case read_bits(path) {
    Ok(b) ->
      case bit_array.to_string(b) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(path <> ": not UTF-8")
      }
    Error(e) -> Error(e)
  }
}

@external(erlang, "fabric_ffi", "write_file")
fn write_bits(path: String, data: BitArray) -> Result(Nil, String)

pub fn write(path: String, text: String) -> Result(Nil, String) {
  write_bits(path, <<text:utf8>>)
}

pub fn write_bytes(path: String, data: BitArray) -> Result(Nil, String) {
  write_bits(path, data)
}

@external(erlang, "fabric_ffi", "exists")
pub fn exists(path: String) -> Bool

@external(erlang, "fabric_ffi", "is_dir")
pub fn is_dir(path: String) -> Bool

/// Names in a directory, sorted (byte order, as Python's sorted() on str for ASCII names).
@external(erlang, "fabric_ffi", "list_dir")
pub fn list_dir(path: String) -> Result(List(String), String)

/// sorted(Path(dir).glob("*" <> suffix)) for a plain suffix such as ".md", as full paths.
pub fn glob(dir: String, suffix: String) -> List(String) {
  case list_dir(dir) {
    Ok(names) ->
      names
      |> list.filter(fn(n) { string.ends_with(n, suffix) })
      |> list.map(fn(n) { join(dir, n) })
    Error(_) -> []
  }
}

/// mkdir(parents=True, exist_ok=True)
pub fn make_dirs(path: String) -> Result(Nil, String) {
  make_dirs_ffi(path)
}

@external(erlang, "fabric_ffi", "make_dirs")
fn make_dirs_ffi(path: String) -> Result(Nil, String)

@external(erlang, "fabric_ffi", "temp_dir")
pub fn temp_dir() -> String

/// shutil.rmtree, ignoring errors.
@external(erlang, "fabric_ffi", "remove_all")
pub fn remove_all(path: String) -> Nil

pub fn join(a: String, b: String) -> String {
  case a, string.starts_with(b, "/") {
    _, True -> b
    "", _ -> b
    _, _ ->
      case string.ends_with(a, "/") {
        True -> a <> b
        False -> a <> "/" <> b
      }
  }
}

/// Path(p).name
pub fn base_name(path: String) -> String {
  case list.last(string.split(path, "/")) {
    Ok(n) -> n
    Error(_) -> path
  }
}

/// Path(p).parent, as a string ("." for a bare name).
pub fn parent(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_] -> "."
    [_, ..rest] ->
      case list.reverse(rest) |> string.join("/") {
        "" -> "/"
        p -> p
      }
    [] -> "."
  }
}

/// Path(p).stem
pub fn stem(path: String) -> String {
  let name = base_name(path)
  case string.split(name, ".") |> list.reverse {
    [_, first, ..rest] if first != "" || rest != [] ->
      list.reverse([first, ..rest]) |> string.join(".")
    _ -> name
  }
}

pub type Run {
  Run(status: Int, stdout: String)
}

@external(erlang, "fabric_ffi", "run")
fn run_ffi(
  command: String,
  args: List(String),
  cwd: String,
) -> Result(#(Int, BitArray), String)

/// subprocess.run(capture_output=True): stdout is captured, stderr passes through.
/// Error only when the command cannot be started.
pub fn run(
  command: String,
  args: List(String),
  cwd: String,
) -> Result(Run, String) {
  case run_ffi(command, args, cwd) {
    Ok(#(status, out)) ->
      case bit_array.to_string(out) {
        Ok(s) -> Ok(Run(status, s))
        Error(_) -> Error(command <> ": output is not UTF-8")
      }
    Error(e) -> Error(e)
  }
}

/// subprocess.run(check=True, ...).stdout; a non-zero status is an error.
pub fn check_output(
  command: String,
  args: List(String),
  cwd: String,
) -> Result(String, String) {
  case run(command, args, cwd) {
    Ok(Run(0, out)) -> Ok(out)
    Ok(Run(status, _)) ->
      Error(
        "Command '"
        <> string.join([command, ..args], " ")
        <> "' returned non-zero exit status "
        <> int.to_string(status)
        <> ".",
      )
    Error(e) -> Error(e)
  }
}

@external(erlang, "fabric_ffi", "sha256_hex")
pub fn sha256_hex(data: BitArray) -> String

@external(erlang, "fabric_ffi", "http")
fn http_ffi(
  method: String,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
) -> Result(#(Int, BitArray), String)

/// One HTTP(S) request; returns the status and the body.
pub fn http(
  method: String,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
) -> Result(#(Int, BitArray), String) {
  http_ffi(method, url, headers, body)
}

/// A gzipped tarball of #(name in the archive, path on disk).
@external(erlang, "fabric_ffi", "tar_gz_create")
pub fn tar_gz_create(
  tarball: String,
  files: List(#(String, String)),
) -> Result(Nil, String)

@external(erlang, "fabric_ffi", "tar_gz_extract")
pub fn tar_gz_extract(tarball: String, dir: String) -> Result(Nil, String)
