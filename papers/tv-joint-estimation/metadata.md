---
title: "When is it worth estimating a TV slot's channels together?"
subtitle: "An exact gain identity for the joint additive step, proved in Agda, and its test on a simulated prime-time benchmark"
author:
  - name: Matheus Hoffmann
    orcid: 0009-0009-1056-7661
date: "November 2026"
version: "Preprint v0 (draft, not peer reviewed)"
keywords:
  - audience forecasting
  - television ratings
  - forecast reconciliation
  - multinomial logit
  - Agda
  - formal verification
abstract: |
  Independent forecasts of the channels of a TV slot miss what a rival's big show takes from
  them. The cheapest joint correction moves every channel's forecast by the same amount, so that
  the forecasts add up to a forecast $p$ of the slot's total. We prove that this step has an exact
  gain: for every slot of $C$ rows, $C\,(\mathrm{SSE}_{\text{alone}} - \mathrm{SSE}_{\text{joint}}) =
  S^2 - \varepsilon^2$, where $S$ is the error of the sum of the independent forecasts and
  $\varepsilon$ the error of $p$. So the step gains if and only if $|\varepsilon| \le |S|$, in
  squared error. From the identity follow a gain of at least $C\delta^2$ when every channel is
  over-forecast by $\delta$, the shape of a big show's effect on its rivals; a band of errors in
  which no channel gets worse; a cost at which the step stops paying; and the same over many
  slots. We also prove the coherence, independence of irrelevant alternatives, diversion and
  inversion properties of a multiplicative joint model, the Joint Competitive Share model. Every
  statement has a written proof and an Agda proof under `--safe`, over exact rationals, for every
  number of rows. On a simulated benchmark of three markets (2,736 test slots, 129 big shows; all
  data synthetic) the identity holds slot by slot on doubles, and its condition explains every
  loss: it held on 30% to 81% of slots, depending on the grouping. With the actual total of the
  channels, the step lowers the WAPE of XGBoost with rival features from 15.0% to 14.1% overall and
  from 21.1% to 16.2% on big shows. With the totals our models forecast, it raises the channels'
  error, because those totals are worse than the sum of the channel forecasts. The identity is
  about squared error in one slot, not about WAPE, expectations or rounding. A public-ratings
  pipeline for the US, the UK and Brazil is in place, but the public lists do not yet give the
  slots that a real test needs.
lang: en-US
papersize: a4
fontsize: 11pt
geometry:
  - top=25mm
  - bottom=25mm
  - left=28mm
  - right=28mm
---
