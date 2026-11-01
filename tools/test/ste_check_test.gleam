import fabric/ste_check.{compare, long_sentences}
import gleam/list
import gleam/string

const o =
  "A claim [@a; @b]. He said \"it is so\" in 1991. **[ANALYSIS]** See Section [-@sec:x]."

pub fn same_facts_in_other_words_test() {
  assert compare(
      o,
      "A claim is true [@a; @b]. In 1991 he said \"it is so\". **[ANALYSIS]** See Section [-@sec:x].",
      False,
    )
    == []
}

pub fn lost_and_added_facts_test() {
  let errs =
    compare(
      o,
      "A claim [@a]. He said \"it is\" in 1992. See Section [-@sec:x].",
      False,
    )
  assert errs
    == [
      "citations lost: ['@b']",
      "quotations lost: ['it is so']",
      "quotations added: ['it is']",
      "numbers lost: ['1991']",
      "numbers added: ['1992']",
      "markers lost: ['ANALYSIS']",
    ]
}

pub fn split_analysis_paragraph_test() {
  assert compare(
      "**[ANALYSIS]** a. b.",
      "**[ANALYSIS]** a.\n\n**[ANALYSIS]** b.",
      False,
    )
    == []
}

pub fn long_sentences_test() {
  let assert [note] =
    long_sentences(string.join(list.repeat("word", 30), " ") <> ".")
  assert string.starts_with(note, "30 words: word word")
  assert string.ends_with(note, "…")
  assert long_sentences("Short one.") == []
}

pub fn translation_keeps_facts_test() {
  let pt =
    "Uma tese [@a; @b]. Ele disse \"it is so\" (em tradução livre: \"é assim\") em 1991. **[ANÁLISE]** Ver a Seção [-@sec:x]."
  assert compare(o, pt, True) == []
  assert compare("Cost 3.5 and 1,000.", "Custo 3,5 e 1.000.", True) == []
}

pub fn translation_loses_facts_test() {
  let errs =
    compare(
      o,
      "Uma tese [@a]. Ele disse \"é assim\" em 1991. Ver a Seção [-@sec:x].",
      True,
    )
  assert errs
    == [
      "citations lost: ['@b']",
      "quotations lost: ['it is so']",
      "markers lost: ['ANALYSIS']",
    ]
}

pub fn front_matter_code_and_urls_are_skipped_test() {
  assert compare(
      "---\nx: 1\n---\nA `9` <https://a.b/2> https://c.d/3 b.",
      "A b.",
      False,
    )
    == []
}

pub fn repr_as_python_test() {
  assert ste_check.repr("it's") == "\"it's\""
  assert ste_check.repr("a'b\"c\\") == "'a\\'b\"c\\\\'"
  assert ste_check.repr("é\t\u{01}") == "'é\\t\\x01'"
}

pub fn counter_elements_sorted_test() {
  assert ste_check.elements(ste_check.counter(["b", "a", "b", "é"]))
    == ["a", "b", "b", "é"]
}
