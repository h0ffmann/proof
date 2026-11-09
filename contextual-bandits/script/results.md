# Output of the video's code

Written by `cabal run video` (haskell/app/Video.hs). Exact arithmetic for pi; Double for the simulations.

## Scenes 1.1 and 3.4: the current belief against the new belief (`beliefs`)

```text
current belief  [0.67, 0.50] -> selects 0
new belief      [0.57, 0.62] -> selects 1
changed its mind? True
```

## Scene 1.3: correct digits per term (`Pi.hs`)

| terms | Leibniz | Gauss-Legendre | Ramanujan |
| --- | --- | --- | --- |
| 1 | 0 | 3 | 7 |
| 2 | 0 | 8 | 16 |
| 3 | 1 | 19 | 24 |
| 4 | 0 | 41 | 32 |
| 5 | 1 | 61 | 40 |
| 6 | 0 | 61 | 48 |
| 100,000 | 5 | · | · |

## Scene 1.3: one arm, Leibniz: exploit pi(N) or explore pi(N+1) (`singleArmed`, 20 rounds, epsilon = 0.2)

| action | times | mean grade of the user |
| --- | --- | --- |
| exploit pi(N) | 9 | 0.14 |
| explore pi(N+1) | 11 | 0.76 |

pi(N) at the end: N = 12, 1 correct digits

## Scene 1.4: three arms, Leibniz, Gauss-Legendre, Ramanujan (`multiArmed`, 20 rounds, epsilon = 0.2)

| arm | pulls | mean grade of the user | correct digits at the end |
| --- | --- | --- | --- |
| Leibniz | 1 | 0.14 | 0 |
| Gauss-Legendre | 3 | 1.00 | 19 |
| Ramanujan | 16 | 1.00 | 61 |

## Scenes 2.3 and 2.4: the A/B test against the bandit rules (`abVsBandit`)

T = 5000, mean of 20 seeds, 2 contexts x 3 arms

| policy | regret |
| --- | --- |
| A/B test (T/2, then commit) | 128.8 |
| A/B without context (T/2, then commit) | 178.9 |
| epsilon-greedy 0.1 | 76.4 |
| UCB beta = 2 | 19.5 |

## Scene 3.2: the outer loop selects the epsilon of the inner loop (`rsiLoop`, 200 episodes of 500 rounds)

| epsilon of the inner agent | times selected | mean gain per round |
| --- | --- | --- |
| 1.0 | 11 | 0.080 |
| 0.5 | 168 | 0.099 |
| 0.1 | 12 | 0.085 |
| 1.0e-2 | 9 | 0.057 |
