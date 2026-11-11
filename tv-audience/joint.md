# Joint estimation of a slot's channels, in Agda

The claim: when it costs little, estimating every channel of a slot together, with the
neighbours, can approximate the audience better than estimating each channel alone, and more so
for big shows and contested slots. [`agda/src/TvAudience/Joint.agda`](../agda/src/TvAudience/Joint.agda)
states this exactly and proves it, under `--safe --without-K`, over exact rationals.

## The setting

A slot has C rows, one for each channel (with the outside audience as one more row when the
group is the whole pool). Each row is the actual audience y and an independent forecast f, made
by a model of that channel alone.

The joint step sees all the rows. It takes a forecast p of the group's total and moves every
forecast by the same amount, so that the forecasts add up to p:

```text
f'_i = f_i - (Σ f - p) / C
```

This is the Euclidean projection of the forecasts onto the plane Σ f = p. It costs one sum and
one division per slot, O(C).

Write T = Σ y for the actual total, S = Σ f - T for the bias of the independent forecasts, and
ε = p - T for the error of the pool forecast. SSE is the sum of squared errors of the slot.

## What is proved

For every slot and every C, with no other assumption than the one in each row:

| Theorem | Statement |
|---|---|
| `reconcile-coherent` | the joint forecasts add up to p |
| `joint-gain` | C · (SSE_alone - SSE_joint) = S² - ε², exactly |
| `joint-le` | \|ε\| ≤ \|S\| implies SSE_joint ≤ SSE_alone |
| `joint-lt` | \|ε\| < \|S\| implies SSE_joint < SSE_alone |
| `joint-known` | with the actual pool (ε = 0), every slot with S ≠ 0 gains |
| `joint-common-bias` | every channel over-forecast by at least δ ≥ 0 and \|ε\| ≤ η: C · gain ≥ (C δ)² - η². With an exact pool, the gain is at least C δ² |
| `channel-no-worse` | with the actual pool, every error in [lo, hi], 0 ≤ lo, hi ≤ 2 lo: no channel's absolute error grows |
| `joint-worth` | with costs c_alone and c_joint: C · (c_joint - c_alone) ≤ S² - ε² implies SSE_joint + c_joint ≤ SSE_alone + c_alone |
| `joint-total` | over a list of slots, each with \|ε\| ≤ \|S\|, the total SSE of the joint method is not larger |

How to read it for TV audiences:

- **Big shows.** A big show on one channel takes viewers that the other channels' own models do
  not see, so they are all over-forecast. That is a common bias δ on every row, and the gain is
  at least C δ²: it grows with the square of the bias.
- **Contested slots.** More channels that contest the slot is a larger C, and the bound C δ²
  grows with C. The neighbours carry the information that a channel's own model does not have.
- **Cheap.** The joint step is O(C). `joint-worth` says how much extra cost the gain pays for.

## What is not proved, and the limits

- **The pool forecast must be good enough.** The gain needs |ε| ≤ |S|: the pool forecast is not
  further from the actual total than the sum of the channel forecasts. This is an assumption,
  and it is a measurement on data, not a theorem. `lopsided` in
  [`JointExamples.agda`](../agda/src/TvAudience/JointExamples.agda) shows that the joint estimate
  is worse without it (SSE 1 to 5/2).
- **Per channel, a band is needed.** The total error falls, but one channel can get worse.
  `uneven` shows a channel that goes from error 0 to error 1 while the total falls from 4 to 2.
  `channel-no-worse` gives a band (every channel over-forecast, the largest bias at most twice
  the smallest) where no channel gets worse.
- **Squared error, one slot at a time.** The theorems are about SSE, not WAPE, and about the
  numbers of a slot, not about a distribution or an expectation.
- **Additive, not multiplicative.** The JCS model of `TvAudience.Jcs` reconciles by shares. These
  theorems are about the additive projection, which is a different joint step.
- **Exact rationals.** Nothing here is about floating-point rounding.

## Run

```bash
bash checks/agda.sh   # every Agda root type-checks, TvAudienceJoint among them (nix develop .#agda)
```

## Measured on the simulated benchmark

[`python/joint_step.py`](python/joint_step.py) applies the joint step to the test set of
`experiment.py` and writes [`joint_step.md`](joint_step.md): how often |ε| ≤ |S| holds, and the
SSE and WAPE before and after, for two groupings (channels with the outside row, channels alone)
and two totals (a forecast, the actual total). `nix develop .#tv-joint --command python3
tv-audience/python/joint_step.py` runs it. The paper
[`papers/tv-joint-estimation`](../papers/tv-joint-estimation/metadata.md) states the theorems with
written proofs and discusses these numbers.
