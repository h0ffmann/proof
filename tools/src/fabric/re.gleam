//// Python's re over Erlang's re (PCRE), compiled with unicode and ucp so that \w, \d and \s
//// match as Python's str patterns do. Write patterns in Python's syntax; PCRE reads the same
//// syntax for everything the scripts used.

import gleam/list

pub type Regex

pub type Flag {
  /// re.I
  Caseless
  /// re.M
  Multiline
  /// re.S
  Dotall
}

@external(erlang, "fabric_ffi", "regex_compile")
fn compile_ffi(pattern: String, flags: List(Flag)) -> Result(Regex, String)

/// re.compile; panics on a bad pattern, since every pattern here is a literal.
pub fn compile(pattern: String, flags: List(Flag)) -> Regex {
  let assert Ok(r) = compile_ffi(pattern, flags)
  r
}

/// bool(r.search(s))
@external(erlang, "fabric_ffi", "regex_check")
pub fn search(r: Regex, s: String) -> Bool

/// Every match as [whole, group 1, ...]; a group that did not take part is "".
@external(erlang, "fabric_ffi", "regex_scan")
pub fn scan(r: Regex, s: String) -> List(List(String))

/// r.search(s): the first match's [whole, group 1, ...].
pub fn first(r: Regex, s: String) -> Result(List(String), Nil) {
  list.first(scan(r, s))
}

/// r.findall(s) for a pattern with one group, or no group.
pub fn findall(r: Regex, s: String) -> List(String) {
  list.map(scan(r, s), fn(m) {
    case m {
      [_, g, ..] -> g
      [w] -> w
      [] -> ""
    }
  })
}

@external(erlang, "fabric_ffi", "regex_replace")
fn replace_ffi(r: Regex, s: String, with: String, all: Bool) -> String

/// r.sub(with, s): `\1` in `with` is group 1 and `&` is the whole match (Erlang's
/// re:replace syntax; write `\&` for a literal &).
pub fn sub(r: Regex, s: String, with: String) -> String {
  replace_ffi(r, s, with, True)
}

/// r.sub(with, s, count=1)
pub fn sub_first(r: Regex, s: String, with: String) -> String {
  replace_ffi(r, s, with, False)
}

/// r.split(s), for a pattern without groups.
@external(erlang, "fabric_ffi", "regex_split")
pub fn split(r: Regex, s: String) -> List(String)
