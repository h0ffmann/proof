# site

The browsable index of proof: one folder with `index.html` and everything it links, that a web
server can serve at any path, because every link in it is relative.

| In the folder | From |
|---|---|
| `index.html`, `style.css` | `build.py` |
| `papers/<name>.pdf` | every paper of [`papers/`](../papers) in each of its editions (`prose`, `prose-ste`, `prose-pt-BR`), and the video script, built with the justfile's `pandoc_opts` and XeLaTeX, as `just paper` and `just script` build them |
| `contextual-bandits/index.html` and the other pages | the Markdown files of `PAGES` in `build.py`, at the path of their source, so that their relative links and images resolve as on GitHub |
| `roteiro/` | the first 1:30 of the video script, with subtitles and no voice (the `roteiro-preview` skill) |
| `docs/diagrams/`, `docs/logo/logo.svg` | as committed |

A link in a page to a file that is not in the folder goes to that file on GitHub, at the commit
the site is built from.

## Build

```bash
just site         # Nix builds the folder into result-site/ (the committed tree, at its commit)
just site-serve   # serves result-site/ at http://localhost:8000
just checks site  # every source of the index exists; no tool needed
```

`default.nix` is the build. `just site` calls it with the nixpkgs of `flake.lock`, so pandoc,
pandoc-crossref, the TeX Live of the paper lab, Python with Pillow and ffmpeg are pinned. Its
output holds only files (`allowedReferences = [ ]`).

## Serve it from another Nix configuration

Fetch the repository at a pinned commit and build `site/` with that configuration's nixpkgs:

```nix
let
  proof = pkgs.fetchFromGitHub {
    owner = "h0ffmann";
    repo = "proof";
    rev = "<commit>";
    hash = "<hash>";
  };
in
pkgs.callPackage "${proof}/site" { rev = "<commit>"; }
```

The result is a folder to serve as it is, for example with nginx: `"/proof/".alias = "${site}/";`.

## Add a page

Add a row to `PAGES` in `build.py`: its section in the index, the Markdown file, one line on what
it is. A new paper in `papers/` and a new diagram need no change here.
