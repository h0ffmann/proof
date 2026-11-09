% Expected: Theorem
% Cantor's theorem: no function from a type onto the sets of that type.
thf(cantor, conjecture,
    ~ ? [F: $i > $i > $o] : ! [Y: $i > $o] : ? [X: $i] : ((F @ X) = Y)).
