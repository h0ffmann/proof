% Expected: Theorem
% The agent depends on the history only through its belief (z3-scala theorems, statement 6):
% a policy that is a function of the belief gives two histories with the same belief the same
% action, for every belief map and every way of acting on a belief.
thf(history, type, history: $tType).
thf(belief, type, belief: $tType).
thf(action, type, action: $tType).
thf(through_belief, conjecture,
    ! [B: history > belief, G: belief > action, H1: history, H2: history] :
      (((B @ H1) = (B @ H2)) => ((G @ (B @ H1)) = (G @ (B @ H2))))).
