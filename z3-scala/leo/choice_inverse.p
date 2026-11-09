% Expected: Theorem
% A surjective function has a right inverse: with choice, which Leo-III's logic has.
thf(surj_right_inverse, conjecture,
    ! [F: $i > $i] : ((! [Y: $i] : ? [X: $i] : ((F @ X) = Y)) => ? [G: $i > $i] : ! [Y: $i] : ((F @ (G @ Y)) = Y))).
