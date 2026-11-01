//// ste-check: the ASD-STE100 text of a paper keeps what the original says.
////
//// An STE pass may change words, never facts. This compares papers/<slug>/prose-ste/ with
//// papers/<slug>/prose/, file by file, and fails when the citation markers (as a multiset), the
//// anchors, the quotations, the numbers or the [ANALYSIS] and [AUTHOR ...] markers differ. It
//// reports, without failing, sentences over 25 words outside quotations, for the STE100.md log.
////
//// With --translation it compares papers/<slug>/prose-pt-BR/ instead: numbers are compared
//// without their separators (3,5 is 3.5), markers are read in Portuguese, and a quotation may
//// gain a translation but never lose its English original.

import fabric/re
import fabric/sys
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

const long = 25

const usage =
  "ste_check — the ASD-STE100 text of a paper keeps what the original says.

An STE pass may change words, never facts. This check compares papers/<slug>/prose-ste/ with
papers/<slug>/prose/, file by file, and fails when any of these differ: the citation markers (as
a multiset), the cross-reference and heading anchors, the quotations, the numbers, and the
[ANALYSIS] and [AUTHOR ...] markers. It also reports, without failing, sentences over 25 words
outside quotations, so the STE100.md log can list them.

With --translation it compares papers/<slug>/prose-pt-BR/ instead, the Brazilian Portuguese
edition: the same facts, except that numbers are compared without their separators (3,5 is 3.5),
the markers are read in Portuguese, and a quotation may gain a translation but never lose its
English original.

    tools/fabric ste-check closed-source
    tools/fabric ste-check --translation closed-source
"

/// A multiset of strings, as Python's Counter.
pub type Counter =
  Dict(String, Int)

pub fn counter(items: List(String)) -> Counter {
  list.fold(items, dict.new(), fn(d, x) {
    dict.upsert(d, x, fn(n) {
      case n {
        option.Some(n) -> n + 1
        option.None -> 1
      }
    })
  })
}

/// Counter a - b: only positive counts stay.
fn minus(a: Counter, b: Counter) -> Counter {
  dict.fold(a, dict.new(), fn(acc, k, n) {
    let m = n - result.unwrap(dict.get(b, k), 0)
    case m > 0 {
      True -> dict.insert(acc, k, m)
      False -> acc
    }
  })
}

/// sorted(c.elements())
pub fn elements(c: Counter) -> List(String) {
  dict.to_list(c)
  |> list.flat_map(fn(p) { list.repeat(p.0, p.1) })
  |> list.sort(string.compare)
}

/// str.split() with no argument: Python's whitespace, empty pieces dropped.
fn words(s: String) -> List(String) {
  re.split(re.compile("[\\s\\x{1c}-\\x{1f}]+", []), s)
  |> list.filter(fn(w) { w != "" })
}

fn strip_code_urls(text: String) -> String {
  let t = re.sub(re.compile("`[^`]*`", []), text, " ")
  let t = re.sub(re.compile("<https?://[^>]+>|https?://\\S+", []), t, " ")
  re.sub(re.compile("^---\\n.*?\\n---\\n", [re.Dotall]), t, "")
}

fn cite_re() {
  re.compile("-?@[A-Za-z][\\w:-]*", [])
}

fn quote_re() {
  re.compile("[\"“]([^\"”]{3,})[\"”]", [])
}

const pt_markers = [
  #("ANÁLISE", "ANALYSIS"),
  #("RELATO DO AUTOR", "AUTHOR ANECDOTE"),
  #("AUTORES A CONFIRMAR", "AUTHORS TO CONFIRM"),
]

fn strip_separators(n: String) -> String {
  re.sub(re.compile("[.,]", []), n, "")
}

/// The facts a pass must keep, by kind, in the order the errors are reported.
pub fn facts(text: String, pt: Bool) -> List(#(String, Counter)) {
  let t = strip_code_urls(text)
  let numbers =
    re.findall(
      re.compile(
        "(?<![\\w@:/.-])\\d[\\d,.]*\\d|(?<![\\w@:/.-])\\d(?![\\w-])",
        [],
      ),
      t,
    )
    |> list.map(rstrip_dots)
  let markers = case pt {
    True ->
      re.findall(
        re.compile(
          "\\*\\*\\[("
            <> string.join(list.map(pt_markers, fn(p) { p.0 }), "|")
            <> ")",
          [],
        ),
        t,
      )
      |> list.map(fn(m) { result.unwrap(list.key_find(pt_markers, m), m) })
    False ->
      re.findall(
        re.compile("\\*\\*\\[(ANALYSIS|AUTHOR ANECDOTE|AUTHORS TO CONFIRM)", []),
        t,
      )
  }
  [
    #("citations", counter(re.findall(cite_re(), t))),
    #("anchors", counter(re.findall(re.compile("\\{[#.][^}]*\\}", []), t))),
    #(
      "quotations",
      counter(
        list.map(re.findall(quote_re(), t), fn(q) { string.join(words(q), " ") }),
      ),
    ),
    #("numbers", case pt {
      True -> counter(list.map(numbers, strip_separators))
      False -> counter(numbers)
    }),
    #("markers", counter(markers)),
  ]
}

/// n.rstrip(".,")
fn rstrip_dots(n: String) -> String {
  case string.ends_with(n, ".") || string.ends_with(n, ",") {
    True -> rstrip_dots(string.drop_end(n, 1))
    False -> n
  }
}

pub fn long_sentences(text: String) -> List(String) {
  let t = strip_code_urls(text)
  let t = re.sub(re.compile("^#.*$|^\\|.*$|^:::.*$", [re.Multiline]), t, " ")
  let t = re.sub(re.compile("\\[@[^\\]]*\\]|\\[-@[^\\]]*\\]", []), t, " ")
  let t = re.sub(quote_re(), t, "Q")
  let has_word = re.compile("\\w", [])
  re.split(
    re.compile("(?<=[.!?])\\s+(?=[A-Z*\\[(])", []),
    string.join(words(t), " "),
  )
  |> list.filter_map(fn(s) {
    let n = list.count(words(s), fn(w) { re.search(has_word, w) })
    case n > long {
      True -> {
        let head =
          string.to_utf_codepoints(s)
          |> list.take(90)
          |> string.from_utf_codepoints
        Ok(int.to_string(n) <> " words: " <> head <> "…")
      }
      False -> Error(Nil)
    }
  })
}

pub fn compare(orig: String, ste: String, translation: Bool) -> List(String) {
  let a = facts(orig, False)
  let b = facts(ste, translation)
  list.flat_map(a, fn(pair) {
    let #(kind, ca) = pair
    let ca = case kind, translation {
      "numbers", True -> counter(list.map(elements(ca), strip_separators))
      _, _ -> ca
    }
    let cb = result.unwrap(list.key_find(b, kind), dict.new())
    let lost = minus(ca, cb)
    let added = minus(cb, ca)
    // Splitting an [ANALYSIS] paragraph in two (the six-sentence rule) repeats its marker;
    // that marks the same interpretation, so an added ANALYSIS marker is not a change.
    let added = case kind {
      "markers" -> dict.delete(added, "ANALYSIS")
      _ -> added
    }
    // A translation may follow an English quotation with its Portuguese version.
    let added = case kind, translation {
      "quotations", True -> dict.new()
      _, _ -> added
    }
    list.flatten([
      report(kind, "lost", lost),
      report(kind, "added", added),
    ])
  })
}

fn report(kind: String, what: String, c: Counter) -> List(String) {
  case dict.is_empty(c) {
    True -> []
    False -> [kind <> " " <> what <> ": " <> repr_list(elements(c))]
  }
}

/// Python's repr() of a list of str.
pub fn repr_list(items: List(String)) -> String {
  "[" <> string.join(list.map(items, repr), ", ") <> "]"
}

/// Python's repr() of a str.
pub fn repr(s: String) -> String {
  let q = case string.contains(s, "'") && !string.contains(s, "\"") {
    True -> "\""
    False -> "'"
  }
  let body =
    string.to_utf_codepoints(s)
    |> list.map(fn(cp) {
      case string.utf_codepoint_to_int(cp) {
        0x5c -> "\\\\"
        0x0a -> "\\n"
        0x0d -> "\\r"
        0x09 -> "\\t"
        0x27 if q == "'" -> "\\'"
        c if c < 0x20 || c == 0x7f -> "\\x" <> hex2(c)
        _ -> string.from_utf_codepoints([cp])
      }
    })
    |> string.concat
  q <> body <> q
}

fn hex2(c: Int) -> String {
  string.lowercase(string.pad_start(int.to_base16(c), 2, "0"))
}

fn read(path: String) -> String {
  let assert Ok(text) = sys.read(path)
  text
}

pub fn check(slug: String, translation: Bool) -> Int {
  let base = "papers/" <> slug
  let ste_dir = case translation {
    True -> base <> "/prose-pt-BR"
    False -> base <> "/prose-ste"
  }
  let #(errs, longs) =
    sys.glob(base <> "/prose", ".md")
    |> list.fold(#([], []), fn(acc, o) {
      let #(errs, longs) = acc
      let name = sys.base_name(o)
      let s = sys.join(ste_dir, name)
      case sys.exists(s) {
        False -> #([s <> " is missing", ..errs], longs)
        True -> {
          let ste = read(s)
          let errs =
            list.fold(compare(read(o), ste, translation), errs, fn(e, x) {
              [name <> ": " <> x, ..e]
            })
          let longs = case translation {
            True -> longs
            False ->
              list.fold(long_sentences(ste), longs, fn(l, x) {
                [name <> ": " <> x, ..l]
              })
          }
          #(errs, longs)
        }
      }
    })
  let errs = list.reverse(errs)
  let longs = list.reverse(longs)
  let meta = ste_dir <> "/00-metadata.md"
  let longs = case sys.exists(meta) && !translation {
    True ->
      list.append(
        longs,
        long_sentences(string.replace(read(meta), "abstract: |", ""))
          |> list.map(fn(l) { "00-metadata.md: " <> l }),
      )
    False -> longs
  }
  list.each(longs, fn(l) { sys.eprintln("ste_check: note: " <> l) })
  list.each(errs, fn(e) { sys.eprintln("ste_check: " <> e) })
  case errs, translation {
    [], True ->
      sys.eprintln(
        "ste_check: "
        <> slug
        <> " pt-BR: citations, anchors, quotations, numbers and markers kept",
      )
    [], False ->
      sys.eprintln(
        "ste_check: "
        <> slug
        <> ": citations, anchors, quotations, numbers and markers unchanged; "
        <> int.to_string(list.length(longs))
        <> " sentence(s) over "
        <> int.to_string(long)
        <> " words",
      )
    _, _ -> Nil
  }
  case errs {
    [] -> 0
    _ -> 1
  }
}

pub fn main(args: List(String)) -> Int {
  let #(translation, rest) = case args {
    ["--translation", ..rest] -> #(True, rest)
    _ -> #(False, args)
  }
  case rest {
    [slug] -> check(slug, translation)
    _ -> {
      sys.eprintln(usage)
      2
    }
  }
}
