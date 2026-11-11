# Lines of code, as a badge: rewrite it between the loc markers in README.md
loc:
    tools/badges/run.sh loc

# Fail if the lines-of-code badge in README.md is out of date
loc-check:
    tools/badges/run.sh loc --check
