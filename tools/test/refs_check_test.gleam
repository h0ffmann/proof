import fabric/refs_check

const bib =
  "@misc{a,\n  url = {https://x}\n}\n@misc{b,\n  title = {t}\n}\n@comment{c,\n}\n"

pub fn entries_test() {
  assert refs_check.entries(bib)
    == [#("a", "\n  url = {https://x}"), #("b", "\n  title = {t}")]
}

pub fn check_test() {
  let log =
    "| Key | Status |\n|---|---|\n| a | verified | x |\n| c | partial | y |\n"
  assert refs_check.check_texts("refs.bib", bib, "REFERENCES.md", Ok(log))
    == [
      "refs.bib: b has no row in REFERENCES.md",
      "refs.bib: b has neither doi nor url",
      "REFERENCES.md: row c is not in refs.bib",
    ]
  assert refs_check.check_texts(
      "refs.bib",
      "@misc{a,\n  doi = {x}\n}",
      "REFERENCES.md",
      Ok("| a | unverified | x |\n"),
    )
    == ["refs.bib: a is unverified; fetch and check it, or remove it"]
  assert refs_check.check_texts(
      "p/refs.bib",
      bib,
      "p/REFERENCES.md",
      Error(Nil),
    )
    == ["p/refs.bib: no REFERENCES.md next to it"]
}

pub fn rows_keep_first_place_last_value_test() {
  assert refs_check.rows(
      "| a | partial |\n| b | verified |\n| a | unverified |\n",
    )
    == [#("a", "unverified"), #("b", "verified")]
}
