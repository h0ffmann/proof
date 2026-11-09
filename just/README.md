# just/

One file of recipes per feature: `just/<feature>.just`. The `justfile` imports each one with
`import?`, so the file can be missing and a pull request that adds a feature adds its own file
instead of editing recipes other pull requests edit. See `AGENTS.md`, "Composable PRs".
