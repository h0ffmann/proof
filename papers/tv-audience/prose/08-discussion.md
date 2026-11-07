# Discussion and limits {#sec:discussion}

The results suggest a division of labour. Trees win on ordinary slots, where the past of a
channel and hour explains most of the future. The joint model wins on big shows and in contested
slots, where the competition decides the outcome. The margin on big shows is 1.2 points and its
interval includes zero, so we state it as a lead, not as a proof.

A hybrid follows from this: keep the JCS structure (pool times shares, one softmax per slot) and
learn the utility with gradient-boosted trees instead of a linear function or a small network.
The neurosymbolic variant shows that the structure accepts a learned utility. It also shows that
a learned utility needs care on rare events.

## Is a neurosymbolic approach suitable?

Yes, for this problem in particular. Audience forecasting has hard rules that hold for every
channel and every night: shares of a pool cannot exceed one, viewers choose one programme at a
time, and a stronger rival takes viewers from the others. These rules are cheap to write down and
expensive to learn from data, above all for rare big shows. A neurosymbolic model writes them into
the architecture and learns only what is uncertain, the utility of each programme. Our first
version matches JCS over all slots and gives the best winner accuracy, but it does not yet beat
JCS on big shows. The constraint layer could also carry more rules: a channel's contractual
broadcast of a match, regulatory news slots, or the rule that a programme that ends at 22h cannot
lead into the 22h slot.

## Limits

1. **Synthetic data.** The benchmark was built from the same structure that JCS assumes: a pool
   and a logit. That favours JCS. On real data the share structure may hold less well, for
   example when viewers record shows or watch on several screens.
2. **One split.** We test on one period with one seed. A rolling-origin evaluation over several
   seeds would give wider and more honest intervals.
3. **Few big shows.** 129 test big shows and 46 contested ones give wide intervals.
4. **The Timestral arm did not run.** Its result is the largest gap in this draft.
5. **Fixed schedules.** We take the line-ups as given. Channels react to each other's schedules,
   sometimes days before broadcast. A model of that scheduling game is a separate question from
   the forecast, and we leave it out.

The next step is the protocol of [@Sec:groundtruth]: frozen forecasts for real big shows on the
nine channels, scored on day 14.

# Statements {.unnumbered}

**Synthetic data.** Every audience figure in [@Sec:data] and [@Sec:results] comes from a
simulation. None describes a real channel or programme. Channel names in [@Sec:groundtruth] name
public data sources only.

**Use of AI.** Claude (Anthropic), an AI assistant, wrote the simulator and the analysis code, ran
it, and drafted this text at the author's request. The author is responsible for the content.

**Reproducibility.** `python3 tv-audience/python/experiment.py` regenerates every number, table and
figure from a fixed seed. `tv-audience/README.md` lists the Python packages it needs.
