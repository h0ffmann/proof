# TV ratings from public sources

A Haskell pipeline that fetches published TV audience figures and writes them as one CSV for
[`tv-audience/`](../../tv-audience/README.md). It gives the real numbers that the ground-truth
protocol of the paper scores against ([`06-ground-truth.md`](../../papers/tv-audience/prose/06-ground-truth.md)).
The experiment itself still runs on simulated data. Nothing here changes `results.md`.

```bash
tools/tv-ratings/run.sh               # fetch every source, then write tv-audience/real/*.csv
tools/tv-ratings/run.sh parse         # read the pages fetched before, with no network
tools/tv-ratings/run.sh nielsen-us    # one source
tools/tv-ratings/run.sh --self-test   # the parsers on pages written for the test (checks/tv-ratings.sh)
```

`run.sh` enters `nix develop .#tv-ratings` ([`nix/tv-ratings.nix`](../../nix/tv-ratings.nix)) by
itself: GHC with its bundled libraries (`containers`, `directory`, `process`, `time`) and curl.
No library outside GHC's own set is used, as AGENTS.md rule 6 allows for `tools/`.

## Sources

| Id | Market | Page | What it gives | Why this source |
|---|---|---|---|---|
| `nielsen-us` | US | [Nielsen Top 10](https://www.nielsen.com/data-center/top-ten/) | the latest week: four lists (Total, Broadcast, Cable, Syndication) of 10 programmes, with viewers aged 2 and over and household rating | The paper's US source (`nielsen2026topten`). The tables are in the page's HTML, and its `robots.txt` allows the path (checked 2026-11-11). |
| `wikipedia-uk` | UK | [List of most watched television broadcasts in the United Kingdom](https://en.wikipedia.org/wiki/List_of_most_watched_television_broadcasts_in_the_United_Kingdom), revision 1383607932 | special events, programmes, films, and the most watched broadcast of each year, in millions | The big shows of the UK with their channels and dates, under CC BY-SA 4.0. The page cites BFI before 1981 and Barb after. |
| `wikipedia-us` | US | [List of most watched television broadcasts in the United States](https://en.wikipedia.org/wiki/List_of_most_watched_television_broadcasts_in_the_United_States), revision 1377092844 | the top telecasts by viewers, without Super Bowls, and by household rating and share | The history of US big shows, from Nielsen figures, under CC BY-SA 4.0. |
| `wikipedia-br` | BR | [Lista de telenovelas brasileiras com maior audiência](https://pt.wikipedia.org/wiki/Lista_de_telenovelas_brasileiras_com_maior_audi%C3%AAncia), revision 71477955 | telenovelas by average household rating in Grande São Paulo, in points and in millions of homes | Brazil's only source that answered (see below), from Kantar IBOPE figures, under CC BY-SA 4.0. |

The Wikipedia pages are read through the Wikimedia REST API at a pinned revision, so two fetches
give the same rows. Move a revision on purpose, in `Sources.hs`, and run the pipeline again.
Nielsen's page is read as it is on the day of the fetch.

Two sources of the paper are not wired:

- **Barb** (UK, `barb2026top50`). Its top 50 page loads its table with JavaScript, from an API on
  another host, with a key in the page. Its terms for that API are not stated, so the pipeline does
  not call it. The UK rows come from Wikipedia until the owner agrees to use Barb's API.
- **Kantar IBOPE Media** (BR, `meio2016ibope`). `kantaribopemedia.com` answered HTTP 403 to the
  fetch on 2026-11-11.

## Output

`tv-audience/real/ratings.csv` has one row per published figure. Its columns:

| Column | Holds |
|---|---|
| `source`, `market` | the id above, and UK, US or BR |
| `list` | which list of the page, as `Traditional TV, Broadcast` or `special events` |
| `period`, `start`, `end` | the date or week as the page writes it, and its first and last day in ISO 8601 (empty when no date was read) |
| `rank` | the rank in the list, or 0 when the list has none |
| `programme`, `channel` | as the page writes them; a simulcast keeps every channel, as `BBC/ITV` |
| `focus` | 1 when a channel of the row is one of the nine channels of the paper's protocol (BBC One, ITV1, Channel 4; ABC, CBS, NBC; Globo, Record, SBT) |
| `metric`, `value`, `unit` | `viewers P2+` or `average audience` in millions, `household rating` in percent, `household share` in percent, or the Brazilian rating in points |

`tv-audience/real/sources.csv` lists each source with its URL, the time of the fetch, its row count
and its licence. The two files are not committed (`tv-audience/real/.gitignore`): the pages change,
and each keeps its own terms.

## Why a slot needs its rivals

The models of `tv-audience/` forecast a channel's audience as its share of the slot's pool, so a
forecast of one channel depends on the forecast of every rival in the slot. The pipeline keeps
every channel a list shows, not only the nine. Two limits remain. The lists are top lists, so a
weak rival in a big show's slot is often missing. And no source here gives the air time, so the
rows of one week cannot yet be put into slots.

## How a page is read

`Html.hs` reads the tables of a page into grids, with rowspan and colspan expanded and footnote
marks, hidden sort keys, scripts and comments left out. `Sources.hs` names, for each table, the
header cells it must find and the columns it reads. A page that loses a table or renames a column
fails with a message that names it; the pipeline never reads a column it did not recognise. For
Nielsen, the four lists must be under the four tabs and have 10 rows each.
