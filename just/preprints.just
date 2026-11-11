# Preprints, as a badge: count the folders of papers/ and rewrite it between the preprints markers in README.md
preprints:
    python3 scripts/preprints.py

# Fail if the preprints badge in README.md is out of date
preprints-check:
    python3 scripts/preprints.py --check
