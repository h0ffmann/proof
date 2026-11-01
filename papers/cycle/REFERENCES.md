---
title: 'Reference log for "Time is a flat circle"'
status: draft
date: 2026-11-01
---

# Reference log

Every entry in [`refs.bib`](refs.bib) was fetched before it was cited. This log records what was
checked and how, so a reviewer can repeat the check. `tools/fabric refs-check` fails when a
`refs.bib` key has no row here, or a row's key is not in `refs.bib`.

Status values: `verified` (source fetched, details match), `partial` (source fetched, a detail
could not be confirmed), `unverified` (not fetched; must not be cited).

| Key | Status | Checked against | Note |
|---|---|---|---|
| nietzsche1910joyful | partial | Project Gutenberg eBook 52124 plain text, 2026-11-01 | title, translator Thomas Common, T. N. Foulis 1910 match; the fetch stopped near §50, so the §341 text is not yet checked |
| nietzsche1999zarathustra | partial | Project Gutenberg eBook 1998 catalogue page, 2026-11-01 | title, translator Thomas Common and release date 1 Dec 1999 match; the recurrence chapters are not yet read |
| nietzsche1913will | partial | Project Gutenberg eBook 52915 HTML, 2026-11-01 | title, Vol. II, translator Ludovici, editor Levy, Foulis 1913 match; the fetch stopped near §555, so §1066 is not yet checked |
| poincare1890trois | partial | Encyclopedia of Mathematics, "Poincaré return theorem", 2026-11-01 | the page cites Acta Math. 13 (1890) 1–270 and states the theorem; the Springer page did not load, so the paper itself and its DOI are not checked |
| noble2014truedetective | verified | Den of Geek review, 2026-11-01 | author Michael Noble, 18 Feb 2014, season 1 episode 5; the review gives the line "time is a flat circle" to the character Reggie Ledoux |
