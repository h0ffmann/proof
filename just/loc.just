# Lines of code per language, as badges: rewrite them between the loc markers in README.md
loc:
    python3 scripts/loc.py

# Fail if the lines-of-code badges in README.md are out of date
loc-check:
    python3 scripts/loc.py --check
