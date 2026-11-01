//// refs-check: every reference a paper cites must have been fetched and logged.
////
//// For each papers/<slug>/refs.bib, the REFERENCES.md next to it must have one table row per
//// BibTeX key, with status verified or partial, and no row for a key that refs.bib lacks. Every
//// entry must carry a doi or url, so a reader can follow it. An `unverified` row fails the
//// check: an agent that could not fetch a source must not cite it (AGENTS.md).
////
////     tools/fabric refs-check papers/*/refs.bib

import fabric/pystr
import fabric/re
import fabric/sys
import gleam/int
import gleam/list
import gleam/string

/// The usage, printed as refs_check.py printed its __doc__.
const doc =
  "refs_check — every reference a paper cites must have been fetched and logged.

For each papers/<slug>/refs.bib, the REFERENCES.md next to it must have one table row per BibTeX
key, with status verified or partial, and no row for a key that refs.bib lacks. Every entry must
carry a doi or url, so a reader can follow it. An `unverified` row fails the check: an agent that
could not fetch a source must not cite it (AGENTS.md).

    tools/fabric refs-check papers/*/refs.bib
"

const ok = ["verified", "partial"]

/// dict(pairs): a key keeps its first place and takes its last value.
fn to_dict(pairs: List(#(String, String))) -> List(#(String, String)) {
  list.fold(pairs, [], fn(acc, pair) {
    case list.key_find(acc, pair.0) {
      Ok(_) -> list.key_set(acc, pair.0, pair.1)
      Error(_) -> [pair, ..acc]
    }
  })
  |> list.reverse
}

/// The BibTeX entries, key to body, @comment left out.
pub fn entries(bib: String) -> List(#(String, String)) {
  re.compile("@(\\w+)\\s*\\{\\s*([^,\\s]+)\\s*,(.*?)\\n\\}", [re.Dotall])
  |> re.scan(bib)
  |> list.filter_map(fn(m) {
    case m {
      [_, kind, key, body] ->
        case string.lowercase(kind) {
          "comment" -> Error(Nil)
          _ -> Ok(#(key, body))
        }
      _ -> Error(Nil)
    }
  })
  |> to_dict
}

/// REFERENCES.md's rows, key to status.
pub fn rows(log: String) -> List(#(String, String)) {
  re.compile(
    "^\\|\\s*([A-Za-z0-9_:-]+)\\s*\\|\\s*(verified|partial|unverified)\\s*\\|",
    [re.Multiline],
  )
  |> re.scan(log)
  |> list.filter_map(fn(m) {
    case m {
      [_, key, status] -> Ok(#(key, status))
      _ -> Error(Nil)
    }
  })
  |> to_dict
}

/// The errors for one refs.bib (named `bib_path`, as printed), given its text and its
/// REFERENCES.md's text, or Error when there is none.
pub fn check_texts(
  bib_path: String,
  bib: String,
  log_path: String,
  log: Result(String, Nil),
) -> List(String) {
  case log {
    Error(_) -> [bib_path <> ": no REFERENCES.md next to it"]
    Ok(log) -> {
      let bib = entries(bib)
      let rows = rows(log)
      let link = re.compile("^\\s*(doi|url)\\s*=", [re.Multiline])
      let per_key =
        list.flat_map(bib, fn(entry) {
          let #(key, body) = entry
          let row = case list.key_find(rows, key) {
            Error(_) -> [
              bib_path <> ": " <> key <> " has no row in REFERENCES.md",
            ]
            Ok(status) ->
              case list.contains(ok, status) {
                True -> []
                False -> [
                  bib_path
                  <> ": "
                  <> key
                  <> " is "
                  <> status
                  <> "; fetch and check it, or remove it",
                ]
              }
          }
          let url = case re.search(link, body) {
            True -> []
            False -> [bib_path <> ": " <> key <> " has neither doi nor url"]
          }
          list.append(row, url)
        })
      let extra =
        list.filter_map(rows, fn(row) {
          case list.key_find(bib, row.0) {
            Ok(_) -> Error(Nil)
            Error(_) ->
              Ok(log_path <> ": row " <> row.0 <> " is not in refs.bib")
          }
        })
      list.append(per_key, extra)
    }
  }
}

fn check(path: String) -> List(String) {
  let shown = pystr.path_str(path)
  let log_path = pystr.path_str(sys.join(sys.parent(shown), "REFERENCES.md"))
  case pystr.read_text(path) {
    Error(e) -> [e]
    Ok(bib) -> {
      let log = case sys.exists(log_path) {
        False -> Error(Nil)
        True ->
          case pystr.read_text(log_path) {
            Ok(t) -> Ok(t)
            Error(_) -> Error(Nil)
          }
      }
      check_texts(shown, bib, log_path, log)
    }
  }
}

pub fn main(args: List(String)) -> Int {
  case args {
    [] -> {
      sys.eprintln(doc)
      2
    }
    _ -> {
      let errs = list.flat_map(args, check)
      list.each(errs, fn(e) { sys.eprintln("refs_check: " <> e) })
      case errs {
        [] -> {
          sys.eprintln(
            "refs_check: "
            <> int.to_string(list.length(args))
            <> " bibliography file(s) ok",
          )
          0
        }
        _ -> 1
      }
    }
  }
}
