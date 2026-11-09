# Lines of code, as a badge: rewrite it between the loc markers in README.md
loc:
    python3 scripts/loc.py

# Fail if the lines-of-code badge in README.md is out of date
loc-check:
    python3 scripts/loc.py --check
