% Expected: not Theorem
% Not a theorem: a function onto its codomain need not be one to one. Leo-III must not prove it.
thf(surj_injective, conjecture,
    ! [F: $i > $i] : ((! [Y: $i] : ? [X: $i] : ((F @ X) = Y)) => ! [A: $i, B: $i] : (((F @ A) = (F @ B)) => (A = B)))).
