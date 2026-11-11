---
title: 'Reference log for "A decision layer for contextual bandits, proved in Agda"'
status: draft
date: 2026-11-11
---

# Reference log

Every entry in [`refs.bib`](refs.bib) was fetched before it was cited. This log records what was
checked and how, so a reviewer can repeat the check. Every `refs.bib` key has a row here, and
every row's key is in `refs.bib`.

Status values: `verified` (source fetched, details match), `partial` (source fetched, a detail
could not be confirmed), `unverified` (not fetched; must not be cited).

| Key | Status | Checked against | Note |
|---|---|---|---|
| li2010contextual | partial | arXiv abstract page 1003.0146, 2026-11-01 (log of `papers/contextual-bandits/`) | title, four authors, 2010-02-28 and DOI match; the page does not name the WWW 2010 venue |
| auer2002finite | verified | Crossref record of DOI 10.1023/A:1013689704352, 2026-11-11 | title, three authors, Machine Learning 47(2-3), pages 235-256, May 2002 |
| lattimore2020bandit | verified | Crossref record of DOI 10.1017/9781108571401 and the free online edition (PDF), 2026-11-11 | title, two authors, Cambridge University Press, 2020. Chapter 19 "Stochastic Linear Bandits": Theorem 19.2 (LinUCB regret under Assumption 19.1), Eq. (19.10) (the per-round optimism step) and Lemma 19.4 (elliptical potential), read in the online edition |
| degenne2026leanbandits | partial | blueprint table of contents, 2026-10-31 (log of `papers/contextual-bandits/`) | the blueprint exists and covers stochastic multi-armed bandits; the year is the access year |
| agda2025safe | partial | the page at the URL, 2026-11-11 | the page lists the features that `--safe` refuses, `postulate` first; the year of the 2.8.0 release is not on the page |
