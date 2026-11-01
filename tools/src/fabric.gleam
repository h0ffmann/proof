//// Paper Fabric's paper checks, as brought to dogma from h0ffmann/closed-source (tools/README.md).
//// Run through `tools/fabric`, which builds this project and starts it at the repository root.

import fabric/refs_check
import fabric/ste_check
import fabric/sys
import gleam/list
import gleam/string

fn commands() -> List(#(String, fn(List(String)) -> Int)) {
  [#("refs-check", refs_check.main), #("ste-check", ste_check.main)]
}

pub fn main() -> Nil {
  case sys.args() {
    [name, ..rest] ->
      case list.key_find(commands(), name) {
        Ok(command) -> sys.exit(command(rest))
        Error(_) -> usage()
      }
    [] -> usage()
  }
}

fn usage() -> Nil {
  sys.eprintln(
    "usage: tools/fabric <command> [args]\ncommands: "
    <> string.join(list.map(commands(), fn(c) { c.0 }), ", "),
  )
  sys.exit(2)
}
