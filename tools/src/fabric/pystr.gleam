//// The bits of Python's str and pathlib that the checks print through: read_text's universal
//// newlines, splitlines, strip, repr, and str(Path(p)).

import fabric/re
import fabric/sys
import gleam/int
import gleam/list
import gleam/string

/// Path.read_text(): "\r\n" and "\r" read as "\n".
pub fn read_text(path: String) -> Result(String, String) {
  case sys.read(path) {
    Ok(s) -> Ok(s |> string.replace("\r\n", "\n") |> string.replace("\r", "\n"))
    Error(e) -> Error(e)
  }
}

/// str.splitlines()
pub fn splitlines(s: String) -> List(String) {
  let r =
    re.compile(
      "\\r\\n|[\\n\\r\\x0b\\x0c\\x1c\\x1d\\x1e\\x{85}\\x{2028}\\x{2029}]",
      [],
    )
  case list.reverse(re.split(r, s)) {
    ["", ..rest] -> list.reverse(rest)
    parts -> list.reverse(parts)
  }
}

/// str.strip()
pub fn strip(s: String) -> String {
  re.sub(re.compile("^[\\s\\x1c-\\x1f]+|[\\s\\x1c-\\x1f]+$", []), s, "")
}

/// repr(s) for a str. isprintable() is approximated: controls, C1 and the usual invisible
/// format and space characters are escaped, as Python escapes them.
pub fn repr(s: String) -> String {
  let q = case string.contains(s, "'") && !string.contains(s, "\"") {
    True -> "\""
    False -> "'"
  }
  let body =
    string.to_utf_codepoints(s)
    |> list.map(fn(cp) {
      let c = string.utf_codepoint_to_int(cp)
      let ch = string.from_utf_codepoints([cp])
      case c {
        0x5c -> "\\\\"
        0x09 -> "\\t"
        0x0a -> "\\n"
        0x0d -> "\\r"
        _ if ch == q -> "\\" <> q
        _ ->
          case printable(c) {
            True -> ch
            False -> escape(c)
          }
      }
    })
    |> string.concat
  q <> body <> q
}

fn printable(c: Int) -> Bool {
  !{
    c < 0x20
    || { c >= 0x7f && c <= 0xa0 }
    || c == 0xad
    || { c >= 0x2000 && c <= 0x200f }
    || { c >= 0x2028 && c <= 0x202f }
    || { c >= 0x205f && c <= 0x206f }
    || c == 0x3000
    || c == 0xfeff
  }
}

fn escape(c: Int) -> String {
  let hex = string.lowercase(int.to_base16(c))
  case c < 0x100, c < 0x10000 {
    True, _ -> "\\x" <> string.pad_start(hex, 2, "0")
    _, True -> "\\u" <> string.pad_start(hex, 4, "0")
    _, _ -> "\\U" <> string.pad_start(hex, 8, "0")
  }
}

/// str(Path(p)): empty and "." parts dropped, "." for nothing.
pub fn path_str(p: String) -> String {
  let parts = string.split(p, "/") |> list.filter(fn(x) { x != "" && x != "." })
  case string.starts_with(p, "/"), parts {
    True, _ -> "/" <> string.join(parts, "/")
    False, [] -> "."
    False, _ -> string.join(parts, "/")
  }
}

/// sorted({x for x in xs if xs.count(x) > 1})
pub fn duplicates(xs: List(String)) -> List(String) {
  xs
  |> list.filter(fn(x) { list.count(xs, fn(y) { y == x }) > 1 })
  |> list.unique
  |> list.sort(string.compare)
}

/// int(s) for a \d+ match; -1 when Erlang cannot read the digits (non-ASCII ones).
pub fn to_int(s: String) -> Int {
  case int.parse(s) {
    Ok(n) -> n
    Error(_) -> -1
  }
}
