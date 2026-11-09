# Lines of code per language, top 5: rewrite the table between the loc markers in README.md
loc:
    python3 scripts/loc.py

# Fail if the lines-of-code table in README.md is out of date
loc-check:
    python3 scripts/loc.py --check
