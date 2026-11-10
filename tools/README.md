# Repository tools

`python tools/check_docs.py --report` lists missing tracked paths and ambiguous
basenames in Markdown, with candidates for ambiguous names. Use `--json` for a
deterministic machine-readable report, `--show-prose` to inspect excluded prose,
`--strict` to fail on findings, or `--selftest` to check the parser. Intentional
future paths and documented historical source exclusions go in
`tools/docs_check_allow.txt`.
