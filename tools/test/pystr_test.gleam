import fabric/pystr

pub fn splitlines_test() {
  assert pystr.splitlines("") == []
  assert pystr.splitlines("a\n\nb\r\nc\n") == ["a", "", "b", "c"]
  assert pystr.splitlines("a\u{2028}b") == ["a", "b"]
}

pub fn strip_test() {
  assert pystr.strip(" \t a b \n") == "a b"
}

pub fn repr_test() {
  assert pystr.repr("x") == "'x'"
  assert pystr.repr("it's") == "\"it's\""
  assert pystr.repr("'\"") == "'\\'\"'"
  assert pystr.repr("a\\b\u{01}\u{a0}é") == "'a\\\\b\\x01\\xa0é'"
}

pub fn path_str_test() {
  assert pystr.path_str("./a//b/./c") == "a/b/c"
  assert pystr.path_str("./") == "."
  assert pystr.path_str("/a/b") == "/a/b"
}

pub fn duplicates_test() {
  assert pystr.duplicates(["b", "a", "b", "c", "a"]) == ["a", "b"]
}
