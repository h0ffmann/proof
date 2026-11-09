---
title: "Who wins the slot?"
subtitle: "Forecasting audiences of big TV shows as a competition between channels: XGBoost, a neural network, Mistral Timestral and a joint competitive share model"
author:
  - name: Matheus Hoffmann
    orcid: 0009-0009-1056-7661
date: "November 2026"
version: "Preprint v0 (draft, not peer reviewed)"
keywords:
  - audience forecasting
  - television ratings
  - discrete choice
  - XGBoost
  - neurosymbolic models
  - forecast reconciliation
abstract: |
  A TV audience forecast for one channel ignores a plain fact: the viewers who watch a big show on
  one channel are not watching the rival channels in the same hour. We compare five forecasters of
  prime-time audiences, seven days ahead: XGBoost, a multilayer perceptron (DNN), Mistral's
  Timestral time-series foundation model, a Joint Competitive Share (JCS) model, and a
  neurosymbolic version of JCS. JCS predicts all channels of a slot together. It forecasts the
  pool of TV viewers in the hour and splits it between the channels and an outside option with a
  multinomial logit that sees every rival's line-up. We test the models on a simulated benchmark of
  three markets with three channels each: 28,620 training and 8,208 test channel-slots, with 129
  big shows in the test period. All data in the benchmark are synthetic. XGBoost with rival
  features has the lowest error over all slots (15.1% WAPE). JCS has the lowest error on big shows
  (20.1% against 21.3%) and on big shows in contested slots (20.9% against 23.5%), but the paired
  95% interval of the big-show difference (-3.3 to +0.6 points) includes zero. The DNN is worse
  than both (20.7% overall). The Timestral arm did not run, because our compute environment could not
  download its weights; its runner is ready. We name nine channels with public ratings (BBC One, ITV1 and Channel 4
  in the UK; ABC, CBS and NBC in the US; Globo, Record and SBT in Brazil) and a protocol that
  scores frozen forecasts 14 days after broadcast. We also show where the Nixtla libraries fit.
lang: en-US
papersize: a4
fontsize: 11pt
geometry:
  - top=25mm
  - bottom=25mm
  - left=28mm
  - right=28mm
---
