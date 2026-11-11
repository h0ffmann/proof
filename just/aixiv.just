# aiXiv: check every papers/*/aixiv.json (no network), and its self-test
aixiv-check:
    scripts/aixiv.sh check --self-test
    scripts/aixiv.sh check

# aiXiv dry run of one paper: build it, then let aiXiv validate it; nothing is published (needs AIXIV_TOKEN)
aixiv-dry-run slug:
    scripts/aixiv.sh build {{slug}}
    scripts/aixiv.sh submit {{slug}}
