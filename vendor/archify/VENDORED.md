# Vendored: Archify

- Upstream: https://github.com/tt-a1i/archify (the `archify/` skill package)
- Version: 3.2.0
- Commit: a4065941f12be7967436261d9934784e381d423c (2026-10-31)
- License: Apache-2.0 (see `LICENSE`, `NOTICE`, `LICENSE-MIT`, `THIRD_PARTY_NOTICES.md`)

## Local changes

None to the source files. Two things are left out:

- `examples/*.html`: pre-rendered example pages (about 13 MB). The JSON examples that the
  authoring guide refers to are kept.
- Everything outside the upstream `archify/` folder (website, tests, benchmarks).

## Update

```bash
git clone --depth 1 https://github.com/tt-a1i/archify /tmp/archify
rm -rf vendor/archify && mkdir -p vendor/archify
(cd /tmp/archify/archify && tar --exclude='examples/*.html' -cf - .) | tar -xf - -C vendor/archify
# then restore this file and update the commit above
```
