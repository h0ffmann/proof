"""How every check in z3/ proves a statement: by refutation.

A theorem "premises imply conclusion" holds when Z3 finds no model of
"premises and not conclusion": the answer `unsat`. A model, when there is one, is a
counterexample and is printed. Each file of z3/ reports one line per statement and ends with
`finish()`, whose exit code is 1 when a statement failed.
"""

from __future__ import annotations

import sys
from fractions import Fraction

from z3 import Not, RatVal, Solver, simplify, unsat

_failures = 0
_checked = 0


def report(name: str, holds: bool, note: str = "") -> None:
    global _failures, _checked
    _checked += 1
    print(f"{'OK  ' if holds else 'FAIL'}  {name:<34} {note}")
    if not holds:
        _failures += 1


def proves(name: str, premises, conclusion, note: str = "") -> None:
    """The theorem: premises imply the conclusion, for every value of the free symbols."""
    s = Solver()
    s.add(*premises)
    s.add(Not(conclusion))
    result = s.check()
    holds = result == unsat
    if not holds:
        note = f"{result}" + (f", counterexample {s.model()}" if result != unsat and s.model() else "")
    report(name, holds, note or "no counterexample (unsat)")


def rational(q: Fraction):
    return RatVal(q.numerator, q.denominator)


def evaluates(name: str, expression, expected: Fraction) -> None:
    """An example: the closed expression equals the expected rational."""
    value = simplify(expression)
    holds = bool(simplify(value == rational(expected)))
    report(name, holds, f"= {value}  (expected {expected})")


def finish(what: str) -> None:
    print()
    if _failures:
        print(f"{what}: {_failures} of {_checked} failed")
        sys.exit(1)
    print(f"{what}: all {_checked} hold")
