# Preprints, as a badge: count the folders of papers/ and rewrite it between the preprints markers in README.md
preprints:
    tools/badges/run.sh preprints

# Fail if the preprints badge in README.md is out of date
preprints-check:
    tools/badges/run.sh preprints --check
