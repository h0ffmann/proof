---
title: "Calm surface, fat tails"
subtitle: "Taleb's fat-tail diagnostics applied to the S&P 500, 1950 to October 2026"
author:
  - name: Matheus Hoffmann
    orcid: 0009-0009-1056-7661
    affiliation: Escola Politécnica, Universidade Federal do Rio de Janeiro
date: "November 2026"
version: "v0 (draft, not peer reviewed)"
keywords:
  - fat tails
  - tail exponent
  - kappa metric
  - value at risk
  - S&P 500
abstract: |
  On 30 October 2026 the S&P 500 had a daily volatility forecast of 0.76%, below its 1950 to 2026
  average of 1.00%. A Gaussian model turns that number into a 99.99% one-day loss of 2.8%. We apply
  the diagnostics of Taleb's *Statistical Consequences of Fat Tails* to 19,330 daily returns and
  find a power-law left tail with exponent near 3 (3.75 after removing volatility clustering). One
  day, 19 October 1987, supplies 52% of the sample's fourth moment, so kurtosis is not a stable
  number. The max-to-sum test shows a finite mean and variance but no convergence of the third and
  fourth moments. Taleb's $\kappa$ is 0.24 for daily returns. Sums of 30 days keep a kurtosis near
  8, so time does not make the returns Gaussian. At today's volatility, a power-law tail gives a
  99.99% one-day loss of 7.2% and an expected shortfall of 9.8%: 2.6 and 3.3 times the Gaussian
  numbers. The gap is small at 99% and grows with the confidence level. This is an educational
  study, not investment advice.
lang: en-US
papersize: a4
fontsize: 11pt
geometry:
  - top=25mm
  - bottom=25mm
  - left=28mm
  - right=28mm
---
